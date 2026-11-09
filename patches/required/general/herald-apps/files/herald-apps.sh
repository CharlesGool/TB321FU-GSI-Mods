# herald-apps 插件(装在 /system/etc/herald_payload/plugins/herald-apps.sh,由 herald-start.sh source)。
# 内置功能 App 的专用通道:每个功能一个 App(装在系统分区,入口注入到设置里),不用配对、不用 token,
#   每个 App 只能跑自己白名单里的命令。用户接触不到 herald 的其他能力。
# 登记:/system/etc/herald_payload/apps/<包名>.allow,每行一个 ERE,请求必须整行完全匹配其中一条。
# 协议(每个 App 自己的 files/ 目录,只服务 user 0):
#   App 写 herald_req.tmp(一行命令)再 rename 成 herald_req;这里 ≤0.2 秒内取走、执行;
#   回包写 herald_resp.tmp 再 rename 成 herald_resp(第一行 ok… / err <原因>,后面 key=value)。
# 鉴权:包装在系统分区(没被 /data/app 的更新盖住);数据目录、files、请求文件的属主都 = 包的 uid。
# 钩子:插件可定义 heraldapp_post_<包名里的 . 换成 _>() { $1 = 请求整行 },输出追加到回包(补字段用)。
# 附带数据:命令登记在 HERALDP_ATTACH("<命令>:<文件名>:<raw|b64>",如 spoof set 的 profile、keybox import 的 base64)时,
#   App 先把数据写进自己 files/<文件名>,再发请求;这里按请求文件同样的规则检查后搬进私有工作目录(插件从 $W 读)。
# 跑在 HERALDP_START 起的独立子进程里,不占主循环。
HAPP_DIR=${HERALD_APPS_DIR:-$PAYDIR/apps}
HAPP_DATA=${HERALD_APPS_DATA:-/data/data}            # 测试时可以换成假的目录
HAPP_W=${HERALD_APPS_W:-/data/local/tmp/herald/.work-apps}   # 私有工作目录(root 0700);herald_sys 的临时文件也放这里(system_server 要能写)
HAPP_CACHE=""                              # "包名:uid:packages.list 的修改时间" 鉴权缓存
HAPP_PL=${HERALD_APPS_PKGLIST:-/data/system/packages.list}   # 装 / 卸 / 更新任何包都会改它

heraldapp_auth() {   # $1 包名;通过时 HAPP_UID = 包的 uid
  _ad=$HAPP_DATA/$1
  [ -d "$_ad/files" ] && [ ! -L "$_ad" ] && [ ! -L "$_ad/files" ] || return 1
  _adu=$(stat -c %u "$_ad" 2>/dev/null); _afu=$(stat -c %u "$_ad/files" 2>/dev/null)
  [ "$_adu" -ge 10000 ] 2>/dev/null && [ "$_afu" = "$_adu" ] || return 1
  # 包列表没变(没有装 / 卸 / 更新过任何包)就沿用上次的鉴权结果,不用每次跑 pm(两次 pm 要 1 秒左右)
  _anow=$(stat -c %Y "$HAPP_PL" 2>/dev/null); [ -n "$_anow" ] || _anow=nolist$(date +%s)
  case " $HAPP_CACHE " in *" $1:$_adu:$_anow "*) HAPP_UID=$_adu; return 0 ;; esac
  _app=$(herald_sys /system/bin/pm path "$1" | grep '^package:')
  case "$_app" in
    package:/system/system_ext/*|package:/system_ext/*|package:/product/*|package:/system/product/*|package:/system/*) ;;
    *) blog "herald-apps: 拒绝 $1,不在系统分区: ${_app:-没装}"; return 1 ;;
  esac
  [ "$(printf '%s\n' "$_app" | grep -c '^package:')" = 1 ] || { blog "herald-apps: 拒绝 $1,pm path 有多行"; return 1; }
  _apu=$(herald_sys /system/bin/cmd package list packages -U "$1" | sed -n "s/^package:$1 uid:\([0-9]*\).*/\1/p" | head -1)
  [ "$_apu" = "$_adu" ] || { blog "herald-apps: 拒绝 $1,uid 对不上 pm=$_apu 目录=$_adu"; return 1; }
  _anc=""; for _ac in $HAPP_CACHE; do case "$_ac" in "$1:"*) ;; *) _anc="$_anc $_ac" ;; esac; done
  HAPP_CACHE="$_anc $1:$_adu:$_anow"; HAPP_UID=$_adu; return 0
}

# 回包:App 目录里 O_EXCL 新建(0600)→ chown / chcon 成 App 自己的(都带 -h,不跟随符号链接)→ rename。
#   必须 chcon:herald 新建的文件只有 s0,App 数据文件带 App 自己的 MLS 类别,级别不等 App 打不开也删不掉。
heraldapp_reply() {   # $1 包名 $2 回包文件
  _af=$HAPP_DATA/$1/files
  _actx=$(stat -c %C "$_af" 2>/dev/null)
  case "$_actx" in u:object_r:app_data_file:s0|u:object_r:app_data_file:s0:c*) ;; *) blog "herald-apps: $1 files 上下文异常 [$_actx]"; return 1 ;; esac
  case "$_actx" in *[!a-z0-9_:,]*) return 1 ;; esac
  rm -f "$_af/herald_resp.tmp" 2>/dev/null
  ( umask 077; set -C; cat "$2" > "$_af/herald_resp.tmp" ) 2>/dev/null || { blog "herald-apps: $1 写不进回包"; return 1; }
  chown -h "$HAPP_UID:$HAPP_UID" "$_af/herald_resp.tmp" 2>/dev/null
  chcon -h "$_actx" "$_af/herald_resp.tmp" 2>/dev/null
  mv -f "$_af/herald_resp.tmp" "$_af/herald_resp" 2>/dev/null
}

heraldapp_attach() {   # $1 包名 $2 命令名:把这条命令登记的附带数据从 App 的 files/ 搬进 $HAPP_W
  for _aa in $HERALDP_ATTACH; do
    _ac=${_aa%%:*}; _at=${_aa#*:}; _afn=${_at%%:*}; _am=${_at#*:}
    case "$_afn" in ""|*[!A-Za-z0-9_.]*) continue ;; esac
    rm -f "$HAPP_W/$_afn"
    [ "$_ac" = "$2" ] || continue
    _src=$HAPP_DATA/$1/files/$_afn
    [ -e "$_src" ] || [ -L "$_src" ] || continue
    if [ -L "$_src" ] || [ ! -f "$_src" ] || [ "$(stat -c %u "$_src" 2>/dev/null)" != "$HAPP_UID" ]; then
      blog "herald-apps: 拒绝 $1 的附带数据 $_afn(不是 App 的普通文件)"; rm -f "$_src"; continue
    fi
    case "$_am" in
      b64) timeout 2 head -c 262144 "$_src" 2>/dev/null | tr -d '\r\n' > "$HAPP_W/$_afn" ;;
      *)   timeout 2 head -c 262144 "$_src" > "$HAPP_W/$_afn" 2>/dev/null ;;
    esac
    rm -f "$_src"
  done
}

heraldapp_once() {   # $1 包名;有请求就处理并返回 0
  _af=$HAPP_DATA/$1/files
  [ -e "$_af/herald_req" ] || [ -L "$_af/herald_req" ] || return 1
  if ! heraldapp_auth "$1"; then rm -f "$_af/herald_req"; return 0; fi
  # 只认 App 自己建的普通文件;先查再读,只取前 200 字节且限时(换成 FIFO 也卡不住)
  if [ -L "$_af/herald_req" ] || [ ! -f "$_af/herald_req" ] || [ "$(stat -c %u "$_af/herald_req" 2>/dev/null)" != "$HAPP_UID" ]; then
    blog "herald-apps: 拒绝 $1,请求文件不是 App 的普通文件"; rm -f "$_af/herald_req"; return 0
  fi
  _aline=$(timeout 2 head -c 200 "$_af/herald_req" 2>/dev/null | head -1 | tr -d '\r')
  rm -f "$_af/herald_req"
  resp=$HAPP_W/resp; : > "$resp"
  grep -v '^[[:space:]]*\(#\|$\)' "$HAPP_DIR/$1.allow" > "$HAPP_W/allow" 2>/dev/null
  if [ -n "$_aline" ] && [ -s "$HAPP_W/allow" ] && printf '%s\n' "$_aline" | grep -qxE -f "$HAPP_W/allow"; then
    blog "herald-apps: $1: $_aline"
    _acmd=${_aline%% *}; _aarg=${_aline#"$_acmd"}; _aarg=${_aarg# }
    heraldapp_attach "$1" "$_acmd"
    if type "heraldp_cmd_$_acmd" >/dev/null 2>&1; then "heraldp_cmd_$_acmd" "$_aarg" > "$resp" 2>&1
    elif type "heraldp_cmdf_$_acmd" >/dev/null 2>&1; then "heraldp_cmdf_$_acmd" "$_aarg"
    else echo "err 系统里没有这个功能($_acmd)" > "$resp"; fi
    _ahook=heraldapp_post_$(echo "$1" | tr . _)
    type "$_ahook" >/dev/null 2>&1 && "$_ahook" "$_aline" >> "$resp" 2>/dev/null
  else
    blog "herald-apps: 拒绝 $1 不在白名单的命令"
    echo "err not allowed" > "$resp"
  fi
  heraldapp_reply "$1" "$resp"; rm -f "$resp"
  return 0
}

heraldapp_loop() {
  W=$HAPP_W                         # herald_sys 用 $W 放临时文件:和主循环分开
  mkdir -p "$HAPP_W"; chown 0:0 "$HAPP_W"; chmod 0700 "$HAPP_W"
  rm -f "$HAPP_W/tick"; mkfifo "$HAPP_W/tick" 2>/dev/null && exec 9<>"$HAPP_W/tick"
  while true; do
    _abusy=0; _aany=0
    for _aal in "$HAPP_DIR"/*.allow; do
      [ -f "$_aal" ] || continue
      _ap=${_aal##*/}; _ap=${_ap%.allow}
      case "$_ap" in ""|*[!A-Za-z0-9._]*) continue ;; esac
      [ -d "$HAPP_DATA/$_ap/files" ] && _aany=1
      heraldapp_once "$_ap" && _abusy=1
    done
    [ $_abusy = 1 ] && continue
    # 装了登记的 App 就每 0.2 秒看一次(App 等 2.5 秒没人取就认为后端不在),一个都没装就 5 秒。
    # 用 read -t 读一个没人写的 FIFO 来等,不每次 fork sleep。
    if [ $_aany = 1 ]; then _at=0.2; else _at=5; fi
    read -t "$_at" -u9 _x 2>/dev/null || sleep "$_at"
  done
}
heraldapp_start() { ( heraldapp_loop ) & }
HERALDP_START="${HERALDP_START:-} heraldapp_start"
