#!/system/bin/sh
# rootless 核心的 broker(由 init 在 u:r:herald 域拉起,见 init.herald.rc)。
# 这里只有"基础能力 + 接入方式",具体功能(attestation 引擎、Wi-Fi 热点…)都是别的补丁装进来的插件:
#   1. 命令通道:命令行(/system/bin/heraldctl 写 /data/local/tmp/herald/req.<id>)和已配对前端 App(files/herald_req)
#   2. 配对:前端 App 的唯一性/随机密钥/uid 校验(pair / unpair / pair_status)
#   3. 工具函数:Settings.Global 读写(herald_getg/setg/delg)、跑系统命令(herald_sys)、日志(log / blog)
#   4. 插件:$PAYDIR/plugins/*.sh 按文件名顺序 source 进本 shell,接入方式见 README「插件接口」
# 内置命令只有 pair / unpair / pair_status / selftest / diag / reboot,其余命令全部来自插件。
set -u
umask 022     # 插件在 $STATE 之类地方建的文件默认 0644/0755,别的进程(如 keystore)要读的不用再 chmod
PAYDIR=/system/etc/herald_payload
STATE=/data/adb/herald              # broker 的状态目录(配对信息等);插件也可以在这里放自己的状态
export LD_LIBRARY_PATH="/apex/com.android.runtime/lib64:/apex/com.android.runtime/lib64/bionic:/system/lib64:/vendor/lib64"

HERALDLOG_META=/metadata/herald_log
log() { echo "[herald-start] $*"; echo "[$(date '+%m-%d %H:%M:%S' 2>/dev/null)] $*" >> "$HERALDLOG_META/herald-start.log" 2>/dev/null; }

mkdir -p "$STATE"
# V86:shell 自己的报错(哪个文件第几行、什么错)写到 /metadata/herald_log/herald-start.err(shell 可读,V84/V85 真机读不到原因)。
#   不用 trap EXIT:mksh 设了 EXIT trap 后,"变量未定义"这类错误会让整个脚本退出(没有 trap 时只中止那一条命令),
#   V85 就是这样把插件里原本无害的报错变成了后端反复退出。
_EL=/metadata/herald_log/herald-start.err
mkdir -p /metadata/herald_log 2>/dev/null || _EL=$STATE/herald-start.err
[ -f "$_EL" ] && [ "$(wc -c < "$_EL" 2>/dev/null || echo 0)" -gt 262144 ] && mv -f "$_EL" "$_EL.old"
echo "[$(date 2>/dev/null)] herald-start 启动 pid $$" >> "$_EL" 2>/dev/null && exec 2>>"$_EL"
[ -f "$HERALDLOG_META/herald-start.log" ] && [ "$(wc -c < "$HERALDLOG_META/herald-start.log" 2>/dev/null || echo 0)" -gt 262144 ] && mv -f "$HERALDLOG_META/herald-start.log" "$HERALDLOG_META/herald-start.log.old"

# ---- V31 控制 broker:特权代执行控制 App 的切换/导入/重启(App 只读写自身 files 目录,broker root 读之)----
# 设计:控制 App 是普通 app(免平台签名/免新 SELinux 类型),把请求写进自己的 CE files 目录;
#   broker 在 herald 域(root+permissive)轮询读取、代执行特权操作(写 DE profile / 调 keymint / 重启)。
#   切换/导入后写 /data/misc/keystore/herald/data/pif_fingerprint.json,重启 → post-fs-data 的 global-pif 应用。
# ★V31 加 keybox 完整控制(导入/导出/状态/吊销检查)+ 本机 RKP 下发(issue/list/import),命令语法逐条
#   核对自 keymint 二进制自身的 --webui-* usage 字符串(非猜测),见 doc/keymint-webui-cli.md。
SHDIR=/data/local/tmp/herald          # V62 命令行通道(heraldctl):shell(uid 2000)可写,只放 req/resp
W=$SHDIR/.work                     # 后端工作目录:附带数据 + 临时文件(root 0700)。
                                   # ★必须留在 /data/local/tmp 下:回包 resp.tmp 在这里生成,带 shell_data_file 标签,
                                   #   rename 到 SHDIR 后 heraldctl(shell 域 enforcing)才读得到。放 /data/adb 会带 adb/system
                                   #   标签,permissive 的 broker 写得进,但 shell 域的 heraldctl 读不了 → 回包空(V1.2 真机回归)。
                                   #   shell 进不了 .work(0700 root),拿不到里面的临时文件;只有 rename 出去的 resp 才给它。
PAIR=$STATE/frontend_pair          # V62 已配对前端: "包名 uid 密钥"(root 0600)
APPFILES=""                        # 已配对前端的 files 目录,收到请求时按 $PAIR 定
# ---- V61 Settings.Global 读写 ----
# V60 实测:broker 里 `settings get` / `dumpsys` 报 "Failed transaction (2147483646)"。cmd/dumpsys 会把 stdout/stderr
# 的 fd 经 binder 交给 system_server,而 `$(...)` 的管道是 herald 域的,enforcing 的 system_server 无权使用它。
# 所以输出一律重定向到 App 数据目录下的普通文件(system_server 可读写),再从文件读回;stdin 给 /dev/null。
# 万一 settings 命令仍失败,退到 `content`(走 ContentProvider,不传 fd)。
herald_getg() {
  case "$1" in ""|*[!A-Za-z0-9_.]*) echo ""; return 1 ;; esac   # 键名限字母数字下划线点,防注入 content --where
  ( unset LD_LIBRARY_PATH; /system/bin/settings get global "$1" >"$W/herald_t1" 2>/dev/null </dev/null )
  _gv=$(cat "$W/herald_t1" 2>/dev/null)
  case "$_gv" in
    ""|*Failure*|*Exception*|*rror*)
      ( unset LD_LIBRARY_PATH; /system/bin/content query --uri content://settings/global --where "name='$1'" >"$W/herald_t1" 2>/dev/null </dev/null )
      _gv=$(sed -n 's/.*, value=//p' "$W/herald_t1" | head -1) ;;
  esac
  rm -f "$W/herald_t1"
  echo "$_gv"
}
herald_setg() {
  case "$1" in ""|*[!A-Za-z0-9_.]*) return 1 ;; esac
  ( unset LD_LIBRARY_PATH; /system/bin/settings put global "$1" "$2" >"$W/herald_t2" 2>&1 </dev/null )
  [ "$(herald_getg "$1")" = "$2" ] && return 0
  ( unset LD_LIBRARY_PATH; /system/bin/content insert --uri content://settings/global --bind "name:s:$1" --bind "value:s:$2" >>"$W/herald_t2" 2>&1 </dev/null )
  [ "$(herald_getg "$1")" = "$2" ]
}
herald_delg() {
  case "$1" in ""|*[!A-Za-z0-9_.]*) return 1 ;; esac
  ( unset LD_LIBRARY_PATH; /system/bin/settings delete global "$1" >"$W/herald_t2" 2>&1 </dev/null )
  case "$(herald_getg "$1")" in ""|null) return 0 ;; esac
  ( unset LD_LIBRARY_PATH; /system/bin/content delete --uri content://settings/global --where "name='$1'" >>"$W/herald_t2" 2>&1 </dev/null )
  case "$(herald_getg "$1")" in ""|null) return 0 ;; esac
  return 1
}
# ---- V62 前后端分离:后端 = 本 broker(root,只执行下面 case 里的白名单命令);前端 = 任意无特权程序 ----
# 两个请求通道,共用同一个命令分发:
#   1) 命令行:/system/bin/heraldctl(adb shell)写 $SHDIR/req,响应 $SHDIR/resp。
#      目录 0770 root:shell,只有 adb shell(uid 2000,要 USB 调试授权)和 root 能写;请求文件属主也必须是 0/2000。
#   2) 前端 App:写自己的 files/herald_req,响应 files/herald_resp。先在 adb 里 `heraldctl pair <包名>` 配对:
#      后端生成随机密钥,存一份在 $PAIR(root 私有),写一份到该 App 的 files/herald_token(root 属主),并记下 uid。
#      之后只认:数据目录属主 = 配对时的 uid、请求文件属主 = 该 uid、files/herald_token 是 root 建的普通文件且内容一致。
# 认证不用写死在程序里的密钥(逆向就能拿到)。配对密钥每台设备随机生成,不在任何程序里;
#   同包名的 App 卸载重装后数据目录被清空、没有密钥,必须重新配对;没通过认证的请求只删除、不回写任何东西。
# 附带数据(set 的 profile JSON / keybox_import 的 base64 / wifi_put 的 key=value 行):
#   命令行 = req 第 2 行起;App = files/herald_profile_in / herald_keybox_b64_in / herald_wifi_in。
#   都先搬进 $W 再执行,命令分支只读 $W。临时文件也放 $W(system_server 经 fd 写文件,不经管道,见上)。
SH_UIDS="0 2000"
# broker 日志:init 服务的 stdout 不落地,单独写一个小文件(超过 64KB 截半)。★放 root 私有的 $STATE,
# 不放 shell 可写的 SHDIR(否则 shell 能用符号链接让 root 把日志写到别处);adb 用 `heraldctl log` 经 broker 读。
blog() {
  _bl=$STATE/broker.log
  if [ -f "$_bl" ] && [ "$(wc -c < "$_bl" 2>/dev/null)" -gt 65536 ]; then
    tail -c 32768 "$_bl" > "$_bl.tmp" 2>/dev/null; mv -f "$_bl.tmp" "$_bl"
  fi
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$_bl" 2>/dev/null; chmod 0644 "$_bl" 2>/dev/null
}
herald_uid_ok() { for _u in $2; do [ "$1" = "$_u" ] && return 0; done; return 1; }
herald_prep() {
  # SHDIR 在 shell 可写的 /data/local/tmp 下,shell 可能把它换成符号链接再让 root chown 目标;是链接就先删掉重建
  [ -L "$SHDIR" ] && rm -f "$SHDIR" 2>/dev/null
  mkdir -p "$STATE" "$W" "$SHDIR" 2>/dev/null
  chown 0:0 "$W" 2>/dev/null; chmod 0700 "$W" 2>/dev/null
  chown 0:2000 "$SHDIR" 2>/dev/null; chmod 0770 "$SHDIR" 2>/dev/null
}
herald_sh_req() {   # 命令行有请求:搬进 $W,返回 0
  [ -d "$W" ] || herald_prep
  # V64:每个 heraldctl 用自己的 req.<id> / resp.<id>。V63 只有一个 req/resp,上一条命令被中途打断
  #   (adb 超时、Ctrl-C)后它的回包会被下一条命令读走,回包整体错位一条。按到达先后取最早的一个。
  _rf=$(ls -1tr "$SHDIR" 2>/dev/null | grep -m1 '^req\.[0-9][0-9.]*$')
  if [ -n "$_rf" ]; then RID=${_rf#req.}
  elif [ -f "$SHDIR/req" ]; then _rf=req; RID=""   # 兼容 V63 的 heraldctl
  else return 1; fi
  mv -f "$SHDIR/$_rf" "$W/req.in" 2>/dev/null || return 1
  if [ -L "$W/req.in" ] || ! herald_uid_ok "$(stat -c %u "$W/req.in" 2>/dev/null)" "$SH_UIDS"; then
    blog "拒绝命令行请求: 属主 uid=$(stat -c %u "$W/req.in" 2>/dev/null) 不是 shell/root 或是符号链接"
    rm -f "$W/req.in"; return 1
  fi
  head -1 "$W/req.in" > "$W/req"
  _first=$(head -1 "$W/req.in"); _first=${_first%% *}
  for _a in $HERALDP_ATTACH; do
    _ac=${_a%%:*}; _t=${_a#*:}; _af=${_t%%:*}; _am=${_t#*:}
    [ "$_first" = "$_ac" ] || continue
    case "$_am" in
      b64) tail -n +2 "$W/req.in" | tr -d '\r\n' > "$W/$_af" ;;
      *)   tail -n +2 "$W/req.in" > "$W/$_af" ;;
    esac
  done
  rm -f "$W/req.in"; CH=sh; return 0
}
herald_app_req() {   # 已配对前端有请求且认证通过:搬进 $W,返回 0
  [ -f "$PAIR" ] || return 1
  _pp=""; _pu=""; _pk=""; _ps=""
  read -r _pp _pu _pk _ps < "$PAIR" 2>/dev/null
  [ -n "$_pk" ] || return 1
  APPFILES=/data/data/$_pp/files
  [ -e "$APPFILES/herald_req" ] || [ -L "$APPFILES/herald_req" ] || return 1
  _du=$(stat -c %u "/data/data/$_pp" 2>/dev/null)
  _ru=$(stat -c %u "$APPFILES/herald_req" 2>/dev/null)
  _tf=$(stat -c '%u:%F' "$APPFILES/herald_token" 2>/dev/null)
  _tk=$(cat "$APPFILES/herald_token" 2>/dev/null)
  if [ "$_du" != "$_pu" ] || [ "$_ru" != "$_pu" ] || [ -L "$APPFILES/herald_req" ] \
     || [ "$_tf" != "0:regular file" ] || [ "$_tk" != "$_pk" ]; then
    blog "拒绝前端请求: pkg=$_pp uid 目录/请求/配对=$_du/$_ru/$_pu token=$_tf"
    rm -f "$APPFILES/herald_req"; return 1
  fi
  head -1 "$APPFILES/herald_req" > "$W/req"; rm -f "$APPFILES/herald_req"
  for _a in $HERALDP_ATTACH; do
    _t=${_a#*:}; _f=${_t%%:*}
    if [ -f "$APPFILES/$_f" ] && [ ! -L "$APPFILES/$_f" ]; then cp -f "$APPFILES/$_f" "$W/$_f"; fi
    rm -f "$APPFILES/$_f"
  done
  PAIR_SCOPES=$_ps; CH=app; return 0
}
herald_reply() {   # 把 $W/resp.tmp 原子地交给发请求的通道(rename 不跟随符号链接)
  if [ "$CH" = sh ]; then
    chmod 0666 "$W/resp.tmp" 2>/dev/null; mv -f "$W/resp.tmp" "$SHDIR/resp${RID:+.$RID}" 2>/dev/null
  else
    # App 的 files 目录归 App 所有:先删临时文件,再用 set -C(O_EXCL)写。App 若在空档塞符号链接,
    # O_EXCL 会让这次写直接失败而不是让 root 写到链接目标——只丢这一条回包,不会被劫持。最后 rename 是原子的。
    rm -f "$APPFILES/herald_resp.tmp" 2>/dev/null
    if ( set -C; cat "$W/resp.tmp" > "$APPFILES/herald_resp.tmp" ) 2>/dev/null; then
      chmod 0644 "$APPFILES/herald_resp.tmp" 2>/dev/null
      mv -f "$APPFILES/herald_resp.tmp" "$APPFILES/herald_resp" 2>/dev/null
    fi
    rm -f "$W/resp.tmp"
  fi
}
herald_pair() {   # $1 = "<包名> [--allow rexec]" 或 "--rotate"(只从命令行通道调用)
  # V74:配对可以带授权范围。--allow rexec = 这个 App 在命令行打开 rexec 窗口期间可以调 rexec(默认不授权)。
  #   --rotate = 给当前已配对的 App 换一个新密钥,授权范围不变(怀疑密钥泄露时用)。
  set -f; set -- $1; set +f          # 关通配再 word-split:包名/选项里的 * ? 不被展开成文件名
  _scopes=""; _pkg=""; _rot=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --rotate) _rot=1 ;;
      --allow) shift; case "$1" in rexec) _scopes=rexec ;; *) echo "err pair --allow 只支持 rexec: [$1]"; return ;; esac ;;
      -*) echo "err pair 不认识的选项: $1"; return ;;
      *) _pkg=$1 ;;
    esac
    shift
  done
  if [ $_rot = 1 ]; then
    [ -f "$PAIR" ] || { echo "err pair 没有已配对的前端,不能 --rotate"; return; }
    [ -z "$_pkg" ] || { echo "err pair --rotate 不带包名(对当前已配对的 App 换钥)"; return; }
    read -r _pkg _ou _ok _scopes < "$PAIR"
  fi
  case "$_pkg" in ""|*[!A-Za-z0-9._]*) echo "err pair 包名不合法: [$_pkg]"; return ;; esac
  _d=/data/data/$_pkg
  [ -d "$_d" ] || { echo "err pair 没装这个包: $_pkg"; return; }
  [ -d "$_d/files" ] || { echo "err pair $_d/files 不存在: 先打开一次该 App(调用一次 getFilesDir())"; return; }
  _u=$(stat -c %u "$_d")
  [ "$_u" -ge 10000 ] 2>/dev/null || { echo "err pair uid=$_u 不是普通 App"; return; }
  _k=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  [ ${#_k} -eq 32 ] || { echo "err pair 生成密钥失败"; return; }
  # App 目录归 App 所有:set -C(O_EXCL)写,防 App 用符号链接把 root 的写劫持到别处
  rm -f "$_d/files/herald_token" 2>/dev/null
  if ( set -C; printf '%s' "$_k" > "$_d/files/herald_token" ) 2>/dev/null \
     && chown 0:0 "$_d/files/herald_token" && chmod 0644 "$_d/files/herald_token"; then :
  else echo "err pair 写不进 $_d/files/herald_token(或已被占位)"; return; fi
  printf '%s %s %s %s\n' "$_pkg" "$_u" "$_k" "$_scopes" > "$PAIR.tmp" && chmod 0600 "$PAIR.tmp" && mv -f "$PAIR.tmp" "$PAIR"
  blog "pair: $_pkg uid=$_u scopes=${_scopes:-none}$([ $_rot = 1 ] && echo ' (rotate)')"
  echo "ok paired $_pkg uid=$_u${_scopes:+ scopes=$_scopes}$([ $_rot = 1 ] && echo ' rotated')"
}
herald_pair_status() {
  if [ ! -f "$PAIR" ]; then echo "ok pair none(没有配对的前端)"; return; fi
  read -r _pp _pu _pk _ps < "$PAIR"
  _du=$(stat -c %u "/data/data/$_pp" 2>/dev/null)
  _tf=$(stat -c '%u:%F' "/data/data/$_pp/files/herald_token" 2>/dev/null)
  _tk=$(cat "/data/data/$_pp/files/herald_token" 2>/dev/null)
  _ok=yes
  [ "$_du" = "$_pu" ] || _ok=no
  [ "$_tf" = "0:regular file" ] && [ "$_tk" = "$_pk" ] || _ok=no
  echo "ok pair pkg=$_pp uid=$_pu current_uid=${_du:-无} token=$([ "$_tk" = "$_pk" ] && echo 一致 || echo 不一致或缺失) valid=$_ok scopes=${_ps:-none}"
}
# 通用:跑系统命令(settings/cmd/dumpsys),输出经 $W 下的文件转出(理由同 herald_getg:binder 那头不能用 herald 域的管道)
herald_sys() {   # 跑系统命令,输出经 $W 下的文件转出(理由同 herald_getg:binder 那头不能用 herald 域的管道)
  ( unset LD_LIBRARY_PATH; "$@" >"$W/herald_t7" 2>&1 </dev/null ); _src=$?
  cat "$W/herald_t7" 2>/dev/null; rm -f "$W/herald_t7"; return $_src
}
# 整数范围检查(插件校验取值用):$1 值 $2 最小 $3 最大
herald_int_in() {   # $1 值 $2 最小 $3 最大
  case "$1" in ""|-|*[!0-9-]*|?*-*) return 1 ;; esac
  [ "$1" -ge "$2" ] 2>/dev/null && [ "$1" -le "$3" ] 2>/dev/null
}

# ---- 插件接口 ----
#   别的补丁往 $PAYDIR/plugins/ 放 <名字>.sh,在这里被 source,和本脚本同一个 shell,能用上面所有函数和变量
#   ($W、$STATE、$PAYDIR、herald_getg/setg/delg、herald_sys、log、blog …)。加载按文件名顺序;
#   有先后依赖的用数字前缀(如 00-xxx.sh 先于 app-spoof.sh)。约定:
#     heraldp_cmd_<命令>()    $1 = 命令后面的整串;标准输出就是回包(第一行以 ok / err 开头)。命令名只许小写字母、数字、下划线
#     heraldp_cmdf_<命令>()   同上,但回包由函数自己写进 "$resp"(要追加、要 cp 文件的用这个)
#     HERALDP_START           追加函数名:加载完所有插件后各调一次(起守护、做一次性初始化)
#     HERALDP_IDLE            追加函数名:主循环空闲时每 5 秒调一次
#     HERALDP_ATTACH          追加 "<命令>:<文件名>:<raw|b64>":这个命令的请求第 2 行起是附带数据,
#                          命令行通道搬进 $W/<文件名>(b64 = 去掉换行);前端 App 通道从自己 files/<文件名> 取
#     HERALDP_SELFTEST        追加函数名:selftest 时各调一次,标准输出并进 selftest 回包
#     HERALDP_DIAG            追加函数名:diag 时各调一次,标准输出并进 diag 回包
HERALDP_START=""; HERALDP_IDLE=""; HERALDP_ATTACH=""; HERALDP_SELFTEST=""; HERALDP_DIAG=""; HERALD_PLUGINS=""
for _pl in "$PAYDIR"/plugins/*.sh; do [ -f "$_pl" ] && { . "$_pl"; HERALD_PLUGINS="$HERALD_PLUGINS ${_pl##*/}"; }; done
for _f in $HERALDP_START; do "$_f"; done
herald_prep
_hot=0; _idlet=0; _cleant=0     # _hot>0 = 刚处理过请求的热身期(0.1s 快轮询);_idlet/_cleant 按累计十分之一秒计
( while true; do
    CH=""; RID=""; PAIR_SCOPES=""
    rm -f "$W/req"; for _a in $HERALDP_ATTACH; do _t=${_a#*:}; rm -f "$W/${_t%%:*}"; done
    if ! herald_sh_req && ! herald_app_req; then
      # 自适应轮询:热身期每 0.1s 看一次(连续操作反应快),平时每 1s。IDLE 钩子和清理按墙上时间算,不随轮询快慢变。
      if [ $_hot -gt 0 ]; then _hot=$((_hot - 1)); _dt=1; else _dt=10; fi
      _idlet=$((_idlet + _dt)); _cleant=$((_cleant + _dt))
      [ $_idlet -ge 50 ] && { for _f in $HERALDP_IDLE; do "$_f"; done; _idlet=0; }                                      # ~每 5 秒
      [ $_cleant -ge 6000 ] && { find "$SHDIR" -maxdepth 1 -name 'resp.*' -mmin +10 -delete 2>/dev/null; _cleant=0; }   # 被打断的回包 10 分钟后清
      [ $_dt = 1 ] && sleep 0.1 || sleep 1
      continue
    fi
    req=$(head -1 "$W/req" 2>/dev/null); rm -f "$W/req"
    blog "$CH${RID:+#$RID}: ${req%% *}"
    cmd=${req%% *}; arg=${req#"$cmd"}; arg=${arg# }
    # ★V34 修复:之前各分支直接写 $APPFILES/herald_resp,App 用"文件存在"当"写完"的信号——shell 的
    #   `>` 重定向一打开文件就立刻存在(0 字节),keymint 子进程(尤其 list 这种要联网拉目录、耗时长的)
    #   还没写完输出前,App 的 800ms 轮询就可能先看到"存在但空"的文件、当成最终结果读走(读到空串)。
    #   命令越慢窗口越宽,list-pif-devices 稳定复现。改成先写临时文件,全部写完后一次性 mv(同文件系统
    #   内 rename 是原子的)到最终路径——App 那边永远只会看到"不存在"或"完整内容",没有中间态。
    resp=$W/resp.tmp
    case "$cmd" in
      # ---- V62 前端配对(只接受命令行通道,App 不能给自己配对)----
      pair)        if [ "$CH" = sh ]; then herald_pair "$arg" > "$resp"; else echo "err pair-only-from-adb" > "$resp"; fi ;;
      unpair)      if [ "$CH" = sh ]; then
                     if [ -f "$PAIR" ]; then read -r _pp _pu _pk _ps < "$PAIR"; rm -f "/data/data/$_pp/files/herald_token"; fi
                     rm -f "$PAIR"; echo "ok unpaired" > "$resp"
                   else echo "err pair-only-from-adb" > "$resp"; fi ;;
      pair_status) herald_pair_status > "$resp" ;;
      # broker 日志(命令历史、被拒请求)。日志已移到 root 私有目录,shell 读不到,由 broker 代读;只开放给命令行通道
      log)         if [ "$CH" = sh ]; then { cat "$STATE/broker.log" 2>/dev/null || echo "(还没有日志)"; } > "$resp"
                   else echo "err log-only-from-adb" > "$resp"; fi ;;
      selftest)
              { echo "uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null | tr -d '\0')"
                echo "selinux=$(getenforce 2>/dev/null)"
                echo "workdir=$W"; herald_pair_status
                echo "plugins=${HERALD_PLUGINS:-(无)}"
                _sv=$(herald_getg herald_selftest); echo "settings_get herald_selftest=[${_sv}]"
                if herald_setg herald_selftest 1; then echo "settings_put=ok"; else echo "settings_put=FAIL $(head -c 200 "$W/herald_t2" 2>/dev/null | tr '\n' ' ')"; fi
                herald_delg herald_selftest >/dev/null 2>&1
                rm -f "$W/herald_t2"
                for _f in $HERALDP_SELFTEST; do "$_f"; done
              } > "$resp" 2>&1 ;;

      # 只读诊断:后端自己的情况 + 各插件登记的段落。shell 读不了 /data 下的私有目录,所以由 broker 代读(固定内容,不接受路径参数)
      diag)
              { echo "== 后端"
                echo "uid=$(id -u) plugins=${HERALD_PLUGINS:-(无)}"
                for _f in $HERALDP_DIAG; do "$_f"; done
              } > "$resp" 2>&1 ;;

      reboot) echo "ok rebooting" > "$resp"
              herald_reply   # 重启前先把响应交出去
              sync; sleep 1
              /system/bin/reboot 2>/dev/null || setprop sys.powerctl reboot
              continue ;;   # 已手动落地+跳过下面统一的 mv(reboot 分支自己处理过)
      *)      # 插件命令(命令名只允许小写字母/数字/下划线)
              case "$cmd" in *[!a-z0-9_]*|"") _pf=; _pg= ;; *) _pf=heraldp_cmd_$cmd; _pg=heraldp_cmdf_$cmd ;; esac
              if [ -n "$_pf" ] && type "$_pf" >/dev/null 2>&1; then "$_pf" "$arg" > "$resp" 2>&1
              elif [ -n "$_pg" ] && type "$_pg" >/dev/null 2>&1; then "$_pg" "$arg"
              else echo "err unknown-cmd:$cmd" > "$resp"; fi ;;
    esac
    herald_reply
    _hot=30     # 处理完请求后进入 ~3 秒热身期(30 × 0.1s),连续命令不必等 1 秒轮询
  done ) &

wait
