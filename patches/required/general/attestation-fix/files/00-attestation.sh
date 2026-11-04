# attestation-fix 的 broker 插件(装在 /system/etc/herald_payload/plugins/00-attestation.sh)。
# 文件名带 00- 是为了排在 app-spoof.sh 前面:后者的顶层代码要用这里定义的 CFG / ENABLE_FLAG。
#   起 keymint / inject 守护(HERALDP_START)、boot-state 覆写、指纹/keybox/RKP/安全补丁命令。
#   这些代码原来在 herald-start.sh 里(V26–V94),拆出来时一行没改,只换了接入方式。
BIN=$PAYDIR/bin
SEED=$PAYDIR/seed
CFG=/data/misc/keystore/herald      # 路径由 keymint 二进制硬编码(strings 核实):配置基 = /data/misc/keystore/herald/
DATA_PIF=$CFG/data/pif_fingerprint.json   # V84:keymint 启动前的设备 ID 对齐要用
LOG=$CFG/logs
RBIN=$CFG/bin
DATA_KEYBOX=$CFG/keybox.xml
ENABLE_FLAG=$CFG/data/global_pif_enabled   # 存在才让 herald-global-pif.sh 真正覆写属性(默认关,见该脚本)

heraldp_start_attestation() {
  mkdir -p "$CFG" "$CFG/data" "$LOG"
# ★V33 修复:$CFG/data/rkp-artifacts 下的本机 RKP 签发结果要求 root:root 私有("RKP result directory
#   must be root-owned and private"),但下面 chown -R 1017:1017 "$CFG" 是给 keystore 用的、会把它
#   一并转成 keystore 属主 —— 每次重启都复发,之前只能靠用户手动 rm -rf 清空才恢复。每次 chown -R
#   后立刻把这个子树纠正回 root:root,而不是依赖用户清空(调用处见下方 fix_rkp_artifacts 两处)。
fix_rkp_artifacts() {
  [ -d "$CFG/data/rkp-artifacts" ] || return 0
  chown -R 0:0 "$CFG/data/rkp-artifacts" 2>/dev/null
  find "$CFG/data/rkp-artifacts" -type d -exec chmod 0700 {} \; 2>/dev/null
  find "$CFG/data/rkp-artifacts" -type f -exec chmod 0600 {} \; 2>/dev/null
}
# keystore uid=1017。init.herald.rc 已给 CAP_CHOWN → chown 到 keystore(镜像 OMK 模块 post-fs-data 的
# chown 1017:1017),keystore 自己就能 traverse/读自己的目录树、keymint 的文件 op 也不卡。
chown -R 1017:1017 "$CFG" 2>/dev/null
fix_rkp_artifacts
chmod 0711 "$CFG" "$CFG/data" 2>/dev/null

# 版本戳 seed:seed 文件 sha 变了就覆盖 /data 里的;用户用 APK 改过的(.user_<name>)保留不动。
# 注意:data/ 下的设备本地状态(vbmeta_state.toml / keymint.dat / rkp-artifacts)**绝不**从 seed 覆盖。
seed_one() {   # seed_one <相对名>
    _n=$1; _src="$SEED/$_n"; _dst="$CFG/$_n"; _gen="$CFG/.gen_$(echo "$_n" | tr / _)"
    [ -f "$_src" ] || return 0
    [ -f "$CFG/.user_$(echo "$_n" | tr / _)" ] && { log "保留用户版 $_n"; return 0; }
    _new=$(sha256sum "$_src" 2>/dev/null | cut -d' ' -f1)
    _old=$(cat "$_gen" 2>/dev/null)
    if [ ! -f "$_dst" ] || [ "$_new" != "$_old" ]; then
        cp -f "$_src" "$_dst" && echo "$_new" > "$_gen"
        log "种入 $_n (gen $_new)"
    fi
}
seed_one keybox.xml
seed_one injector.toml
seed_one config.toml
seed_one pif_fingerprint.json       # 种到 CFG 根;keymint 首次会迁到 data/pif_fingerprint.json
# pif 实际读 data/ 下;若 data/ 没有就从根拷一份兜底
[ -f "$CFG/data/pif_fingerprint.json" ] || cp -f "$SEED/pif_fingerprint.json" "$CFG/data/pif_fingerprint.json" 2>/dev/null
# ★vbmeta_state.toml:预置已验证能过三绿的 pinned vb_key。keymint vb_key="auto" 下若 data 无此文件,
# 会现场派生并 persist,而 persist 在 herald 域 EPERM(os err 1)→ keymint fatal → rpc.sock 不起 → 注入废。
# 预置后 keymint 读现成 pinned key、永不 persist,规避崩溃(data 被清/重启后首 boot 自动重种 = 自恢复)。
if [ -f "$SEED/vbmeta_state.toml" ] && [ ! -f "$CFG/data/vbmeta_state.toml" ]; then
    cp -f "$SEED/vbmeta_state.toml" "$CFG/data/vbmeta_state.toml"
    chown 1017:1017 "$CFG/data/vbmeta_state.toml" 2>/dev/null
    log "种入 data/vbmeta_state.toml(pinned vb_key,防 persist EPERM 崩)"
fi
chmod 0600 "$CFG"/keybox.xml "$CFG"/config.toml "$CFG"/injector.toml 2>/dev/null  # keymint(root)读,不对 other 开

# ---- 关键:inject 从可写的 herald_exec 目录运行 + 部署 payload ----
# inject(内嵌 payload .so)用 /proc/self/exe 定位自身、把 payload 部署在自身所在目录再让
# keystore2 dlopen。烤在只读 /system 则部署不了、且 keystore 不能 exec /data 的 .so(EACCES)。
# 故首 boot 把二进制复制到可写的 $CFG/bin;该目录由 sepolicy 的 type_transition 自动落
# herald_exec 标签(keystore 已放行 read/execute/map herald_exec),fd handoff 即可成(绕 namespace)。
RBIN=$CFG/bin
mkdir -p "$RBIN"                       # type_transition: herald 在 keystore_data_file 下建 "bin" → herald_exec
cp -f "$BIN/keymint" "$RBIN/keymint" 2>/dev/null   # 在 herald_exec 目录内创建 → 文件自动 herald_exec
cp -f "$BIN/inject"  "$RBIN/inject"  2>/dev/null
chmod 0755 "$RBIN" "$RBIN/keymint" "$RBIN/inject" 2>/dev/null   # 0755:keystore(1017,other)能 traverse+读
log "运行目录 $RBIN(herald_exec,0755);keymint/inject 已就位"

# ★Bug A 修复:data 目录及其中所有文件必须始终 keystore:keystore。keymint 启动后 drop 到 keystore(1017),
#   若 keymaster.db/keymint.dat 是上一轮以 root 跑时建的(root:root)→ keystore 打不开 → SQLite err14 → panic。
#   上面 seed 的配置、复制的二进制都是 root 建的,这里统一 chown 到 keystore;Bug B 崩溃期遗留的 root 属主 db
#   也一并纠正(对照 OMK 模块 post-fs-data 的 chown 1017:1017,让 keymint 全程以 keystore 建/开 db)。
chown -R 1017:1017 "$CFG" 2>/dev/null
fix_rkp_artifacts                              # 这次 chown -R 同样会误转 rkp-artifacts,纠正回 root
chmod 0755 "$RBIN" 2>/dev/null                 # chown 后再确保 bin 可 traverse

# ★V39 修复(用户用 Hunter App 实测抓到,要求"安全补丁要么全跟全局伪装开关走,要么都不碰"):
#   keymint 自己内置一个"特权 resetprop helper",每次开机都会把 ro.build.version.security_patch /
#   ro.vendor.build.security_patch 同步成它认证层 config.toml 里硬编的 patch(当前 2026-10-05)——
#   这是给 attestation 证书的 RootOfTrust/patch 声明用的(keymint 启动早期一次性 setHalInfo 缓存,
#   后续签证书用这份缓存值、不是每次重读属性),跟我们的 global_pif_enabled 完全无关、从 V27 引擎
#   上线起就一直这样跑。证书声明这层必须一直在(Part1 引擎核心能力,不该跟着伪装开关关掉),但展示层
#   的属性值(getprop/Build.VERSION.SECURITY_PATCH)该跟着开关走——事后纠正属性值是安全的:不影响
#   已经缓存进 HAL 的证书声明,只影响之后读属性/Java 字段看到的值。先在 keymint 还没跑之前把真机
#   build.prop 的原值记下来,keymint 启动后台等它自己同步完,全局伪装关着就纠正回真机值。
REAL_SPATCH_SYS=$(getprop ro.build.version.security_patch 2>/dev/null)
REAL_SPATCH_VENDOR=$(getprop ro.vendor.build.security_patch 2>/dev/null)

# V73:keymint 启动时要把 ro.build.version.security_patch / ro.vendor.build.security_patch 同步成 config.toml [trust] 里的日期,
#   写不了(它只在 /data/adb/*/bin、/system_ext/bin、/system/bin 找 resetprop,我们故意不放)就 fatal 退出,2 秒后重起,无限循环
#   (V68 起底包是本机真实身份、补丁 2025-05-05,和 config 里的 2026-10-05 不一样才暴露;V66 的烤入身份补丁恰好等于 config)。
#   办法:启动前先用自带 resetprop 把这两个属性设成 config 里的值——keymint 看到已经一致就不用写。
#   全局伪装关着时,下面 15 秒后的纠正会把它们改回真机值(伪装开着则保持,和 profile 一致)。
CFG_PATCH=$(sed -n '/^\[trust\]/,/^\[/{s/^security_patch *= *"\([0-9-]*\)".*/\1/p}' "$CFG/config.toml" 2>/dev/null | head -1)
case "$CFG_PATCH" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    if [ -x "$BIN/resetprop" ]; then
      "$BIN/resetprop" -n ro.build.version.security_patch "$CFG_PATCH" 2>/dev/null
      "$BIN/resetprop" -n ro.vendor.build.security_patch "$CFG_PATCH" 2>/dev/null
      log "keymint 启动前:security_patch 属性预先对齐 config.toml 的 $CFG_PATCH(真机值 sys=$REAL_SPATCH_SYS vendor=$REAL_SPATCH_VENDOR)"
    fi ;;
  *) log "keymint 启动前:读不到 config.toml [trust] security_patch,不预对齐" ;;
esac

# V84:按 App 伪装下 Play 商店申请带设备 ID 的密钥认证,带的是伪装值(Google/Pixel);keymint 的 TA 拿它跟自己登记的
#   设备 ID 比对,登记的是真机(Lenovo/TB321FU)→ "attestation ID mismatch for manufacturer"(V83 真机)。
#   做法:按 App 模式且伪装开着时,① config.toml [device] 的五项改成 profile 值;② keymint 启动前把
#   ro.product.{brand,device,manufacturer,model,name} 临时 resetprop 成 profile 值(TA 启动时登记),15 秒后改回真机值。
#   Java 层 Build.* 在 zygote 里已按真值冻结,窗口里 fork 的 App 不受影响;窗口只有开机后约 15 秒。
#   其他情况(全局模式 / 伪装关)[device] 恢复成种子里的真机值。
_dev_set() {   # _dev_set <key> <value>:改 config.toml [device] 里的一项
  sed '/^\[device\]/,/^\[/ s/^'"$1"' = "[^"]*"/'"$1"' = "'"$2"'"/' "$CFG/config.toml" > "$CFG/.herald_cfd" 2>/dev/null \
    && grep -q "^$1 = \"$2\"" "$CFG/.herald_cfd" && cat "$CFG/.herald_cfd" > "$CFG/config.toml"
  rm -f "$CFG/.herald_cfd"
}
_pj() { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p' "$DATA_PIF" 2>/dev/null | head -1 | sed 's#\\/#/#g'; }
# V92:keymint 的设备 ID 身份,和 herald-global-pif.sh 写给 App 的伪装身份用【同一套推导】:
#   brand/device/manufacturer 在设备 profile(keymint --webui-apply-pif-fingerprint 写的)里常常没有,
#   是运行时从 fingerprint 推的。V84–V90 这里直接读 json → 读到空 → 下面的守卫不过 → 整段跳过 →
#   config.toml [device] 从没被改过、一直是真机 Lenovo → vending 的 generateKey 比对第一个字段就 -66。
#   推导逻辑必须和 herald-global-pif.sh 的"字段补全"一字不差,否则 TA 登记的和 App 看到的 Build.* 对不上。
_resolve_pif_identity() {
  _b=$(_pj brand); _d=$(_pj device); _m=$(_pj manufacturer); _mo=$(_pj model); _p=$(_pj product)
  _fp=$(_pj fingerprint)
  if [ -n "$_fp" ]; then
    [ -n "$_b" ] || _b=$(echo "$_fp" | cut -d/ -f1)
    [ -n "$_p" ] || _p=$(echo "$_fp" | cut -d/ -f2)
    [ -n "$_d" ] || _d=$(echo "$_fp" | cut -d/ -f3 | cut -d: -f1)
    [ -n "$_m" ] || _m="$(echo "$_b" | cut -c1 | tr 'a-z' 'A-Z')$(echo "$_b" | cut -c2-)"
  fi
}
IDS_SWAPPED=0
if [ -f "$CFG/config.toml" ]; then
  if [ -f /system/etc/herald_payload/app-spoof/targets.default ] && [ "$(cat "$CFG/data/spoof_mode" 2>/dev/null)" != global ] \
     && [ -f "$CFG/data/global_pif_enabled" ] && [ -f "$DATA_PIF" ]; then
    _resolve_pif_identity
    if [ -n "$_b" ] && [ -n "$_d" ] && [ -n "$_m" ] && [ -n "$_mo" ] && [ -n "$_p" ]; then
      _dev_set brand "$_b"; _dev_set device "$_d"; _dev_set manufacturer "$_m"; _dev_set model "$_mo"; _dev_set product "$_p"
      # V92:逆向 keymint 二进制确认——它的设备 ID 认证读的是【系统属性】ro.product.{brand,device,name,manufacturer,model}
      #   (含 ro.product.vendor.* 兜底),不是 config.toml [device](那是电话号码伪装用的,V91 改它没用)。
      #   keymint 有 SetAttestationIds/"already set",说明设备 ID 启动时登记一次并缓存。所以:启动 keymint 前把这些属性
      #   设成 profile 值,登记完(15 秒)再改回真机值——相机 HAL/相机 app 在开机 15 秒后才会读,读到的是真机值,不崩。
      #   V84 本想这么做但因空变量从没执行;V91 推导已修,这里把窗口真正接上。config.toml [device] 也一并写(无害)。
      _idt="$STATE/ids_targets"; _ido="$STATE/ids_orig"; : > "$_idt"; : > "$_ido"
      # 逐条登记:新值写 ids_targets,当前真机值写 ids_orig(窗口关闭时照这个改回)。TAB 分隔,值里只有空格不含 TAB。
      # 不用 "名|值" 再拆——mksh 的 ${x%%|*} 把 | 当模式"或",会拆空(真机坑,V92 实测)。
      _idadd() {   # $1 属性名 $2 新值。bare 五个必设;带分区前缀/_for_attestation 的,当前没有就不碰(免得留空属性)
        _ov=$(getprop "$1" 2>/dev/null)
        case "$1" in
          ro.product.brand|ro.product.device|ro.product.name|ro.product.manufacturer|ro.product.model) ;;
          *) [ -n "$_ov" ] || return 0 ;;
        esac
        printf '%s\t%s\n' "$1" "$2" >> "$_idt"; printf '%s\t%s\n' "$1" "$_ov" >> "$_ido"
      }
      # V95:V94 已修时序(读回确认),但测试方提出 keymint 可能读的是某个分区变体而非 bare。逆向 keymint 只见到 bare
      #   ro.product.{brand,model} 和 device/name/manufacturer/serialno,没见到分区变体/_for_attestation 字符串;
      #   不过为一次刷机把"属性来源"也排除掉,这里把所有分区前缀 + *_for_attestation 都纳入窗口(临时,15 秒后全部还原,
      #   相机只读 bare,已覆盖)。谁都对不上就不是属性来源的问题。
      for _pfx in "" system. product. odm. system_ext. vendor. bootimage. vendor_dlkm.; do
        _idadd "ro.product.${_pfx}brand" "$_b";        _idadd "ro.product.${_pfx}device" "$_d"
        _idadd "ro.product.${_pfx}name" "$_p";         _idadd "ro.product.${_pfx}manufacturer" "$_m"
        _idadd "ro.product.${_pfx}model" "$_mo"
      done
      _idadd ro.product.brand_for_attestation "$_b";        _idadd ro.product.device_for_attestation "$_d"
      _idadd ro.product.name_for_attestation "$_p";         _idadd ro.product.manufacturer_for_attestation "$_m"
      _idadd ro.product.model_for_attestation "$_mo"
      [ -x "$BIN/resetprop" ] && IDS_SWAPPED=1
      log "按 App 伪装:keymint 设备 ID 走属性窗口(全分区+for_attestation,启动登记 $_b/$_mo,登记后还原);config.toml [device] 也已写"
    fi
  else
    for _k in brand device manufacturer model product; do
      _v=$(sed -n '/^\[device\]/,/^\[/{s/^'"$_k"' = "\([^"]*\)".*/\1/p}' "$SEED/config.toml" 2>/dev/null | head -1)
      [ -n "$_v" ] && _dev_set "$_k" "$_v"
    done
  fi
fi

# ---- 守护:keymint(从可写 herald_exec 目录跑)----
# V91:keymint 每次启动(包括崩了被重起)都在启动时登记设备 ID。按 App 伪装下,每次启动前把 ro.product.* 临时设成
#   profile 值,15 秒后改回真机值;用令牌防止上一轮的"改回"落在下一轮的窗口里。V84–V88 只在开机第一次这样做,
#   keymint 之后重启就登记回 Lenovo,Play 认证仍 -66(V88 真机)。
IDS_OPENS=""
_ids_write() { while IFS="$(printf '\t')" read -r _pn _pv; do [ -n "$_pn" ] && "$BIN/resetprop" -n "$_pn" "$_pv" 2>/dev/null; done < "$1"; }
herald_ids_open() {
  [ "$IDS_SWAPPED" = 1 ] || return 0
  # keymint 反复崩溃重启时不能一直开窗口(改回永远轮不到,属性会一直停在伪装值,相机又会崩):60 秒内开过 3 次就不开了
  _now=$(date +%s 2>/dev/null || echo 0); _recent=""; _cnt=0
  for _t in $IDS_OPENS; do [ $((_now - _t)) -lt 60 ] && { _recent="$_recent $_t"; _cnt=$((_cnt + 1)); }; done
  if [ "$_cnt" -ge 3 ]; then IDS_OPENS=$_recent; log "keymint 60 秒内重启 $_cnt 次,这次不开设备 ID 窗口(属性保持真机值,避免相机长期受影响)"; return 0; fi
  IDS_OPENS="$_recent $_now"
  _ids_write "$STATE/ids_targets"
  # V94:读回确认 ro.product.brand 真的变成 google 再返回(从而 keymint 启动一定在属性生效之后)。
  #   V92 真机日志坐实竞态:resetprop 10 条在设备上要一两秒才生效,keymint 08:07:06.79 就起来读到的还是 Lenovo、
  #   登记后缓存一整天,每小时 Play 重认证都比 Lenovo → -66。这里最多等 4 秒(20×0.2s),属性对了立刻放行。
  _w=0
  while [ "$_w" -lt 20 ]; do [ "$(getprop ro.product.brand 2>/dev/null)" = "$_b" ] && break; _w=$((_w + 1)); sleep 0.2; done
  _tok=$$.$_now.$RANDOM; echo "$_tok" > "$STATE/ids_token" 2>/dev/null
  ( sleep 15
    [ "$(cat "$STATE/ids_token" 2>/dev/null)" = "$_tok" ] || exit 0
    _ids_write "$STATE/ids_orig"
    log "设备 ID 窗口关闭:ro.product.* 已改回真机值" ) &
  log "keymint 启动:ro.product.brand=$(getprop ro.product.brand)(等了 $((_w * 200))ms 确认=$_b),设备 ID 窗口 15 秒"
}
# V92 诊断:开机头 60 秒每 3 秒把 keymint 认证读的那几个属性快照到 /metadata/herald_log/ids-window.log,
#   配合 keymint-err.log 的时间戳,一次开机就能确认 keymint 登记设备 ID 的那一刻属性到底是不是 google。
[ "$IDS_SWAPPED" = 1 ] && ( _i=0; while [ "$_i" -lt 20 ]; do
    printf '[%s] brand=%s device=%s name=%s manufacturer=%s model=%s | vendor.brand=%s vendor.manufacturer=%s\n' \
      "$(date '+%H:%M:%S' 2>/dev/null)" "$(getprop ro.product.brand)" "$(getprop ro.product.device)" \
      "$(getprop ro.product.name)" "$(getprop ro.product.manufacturer)" "$(getprop ro.product.model)" \
      "$(getprop ro.product.vendor.brand)" "$(getprop ro.product.vendor.manufacturer)" >> "$HERALDLOG_META/ids-window.log" 2>/dev/null
    _i=$((_i + 1)); sleep 3
  done ) &
# keymint 日志里的关键行(ID 不匹配、致命错误)镜像到 /metadata/herald_log/keymint-err.log(V88 真机:keymint 日志 shell/rexec 读不到)
( while true; do
    sleep 30
    for _kl in "$LOG"/keymint*.log; do
      [ -f "$_kl" ] || continue
      grep -E 'mismatch|CannotAttestIds|fatal|Failed to retrieve attestation IDs|ErrorCode\(-66\)' "$_kl" 2>/dev/null | tail -n 200
    done > "$HERALDLOG_META/keymint-err.log.new" 2>/dev/null && mv -f "$HERALDLOG_META/keymint-err.log.new" "$HERALDLOG_META/keymint-err.log" 2>/dev/null
  done ) &
( cd "$RBIN" 2>/dev/null
  while true; do
    herald_ids_open
    "$RBIN/keymint" >> "$LOG/keymint.boot.log" 2>&1
    log "keymint 退出 rc=$?,2s 后重起"
    sleep 2
  done ) &

( sleep 15   # 等 keymint 自己的内置同步跑完(设备 ID 窗口的改回在 herald_ids_open 里)
  if [ ! -f "$CFG/data/global_pif_enabled" ] && [ -n "$REAL_SPATCH_SYS" ]; then
    RP=$BIN/resetprop
    if [ -x "$RP" ]; then
      "$RP" -n ro.build.version.security_patch "$REAL_SPATCH_SYS" 2>/dev/null
      [ -n "$REAL_SPATCH_VENDOR" ] && "$RP" -n ro.vendor.build.security_patch "$REAL_SPATCH_VENDOR" 2>/dev/null
      log "全局伪装关闭:已把 keymint 内置同步覆盖掉的 security_patch 纠正回真机值 $REAL_SPATCH_SYS"
    fi
  fi
) &

# ---- 守护:inject(Bug C:只 "injection completed" 不算,要 binder hook 真 committed 才算成)----
# 根因:keystore2 没完全就绪就注入 → payload 入口 returned 但 "Failed to commit any binder ioctl hooks"
#   /或根本没 "committed … hook(s)" → .so 虽 mapped(grep inject>0)但零拦截。
# 对策:keystore2 出现后先等它就绪;注入后读 injector.log 新增行,有 "committed … hook(s)" 才算成功;
#   没有(或 "Failed to commit")就 kill keystore2 让它干净重启、下一轮重注(参考 OMK daemon-injector 重试,
#   但补上 hook-commit 校验——OMK 原版只看 maps 不够)。每轮顺带 chmod 0755 bin(keymint 会把目录树 chmod 回 0700)。
INJLOG=$LOG/injector.log            # payload 从 keystore2 内部写的结构化日志(committed/Failed 都在这)
fails=0
( while true; do
    chmod 0755 "$RBIN" 2>/dev/null; chmod 0755 "$RBIN"/*.so 2>/dev/null
    pid=$(pidof keystore2 2>/dev/null)
    [ -z "$pid" ] && { sleep 2; continue; }

    # 该 pid 已确认注入且 hook committed → 歇着
    if [ -f "$STATE/.hook_ok" ] && [ "$(cat "$STATE/.hook_ok" 2>/dev/null)" = "$pid" ]; then
        sleep 5; continue
    fi

    # keystore2 刚出现:等它完全就绪再注(太早注 hook 装不上)
    sleep 5
    pid=$(pidof keystore2 2>/dev/null); [ -z "$pid" ] && continue
    before=$(wc -l < "$INJLOG" 2>/dev/null || echo 0)
    log "注入 keystore2 pid=$pid(inject@$RBIN,第 $((fails+1)) 次)"
    "$RBIN/inject" >> "$LOG/inject.boot.log" 2>&1
    chmod 0755 "$RBIN"/*.so 2>/dev/null
    sleep 2                          # 等 payload 把 committed/Failed 写进 injector.log
    newlog=$(tail -n "+$((before+1))" "$INJLOG" 2>/dev/null)

    if echo "$newlog" | grep -qi "committed .*hook"; then
        echo "$pid" > "$STATE/.hook_ok"; fails=0
        log "✓ 注入成功且 binder hook committed pid=$pid"
        # ★用户报告(2026-11):部分检测器把这个特征当成 KernelSU 的 track_throne 判红——
        #   inject 自带"自动目标发现"(auto_targets.rs),会监听/改写 packages.list 并遍历 /data/app
        #   来跟踪新装 App,行为模式和 KernelSU 撞了。injector.toml 的 scoop 已经固定写了要伪装的包名,
        #   不靠自动发现也够用,所以每次新注入成功后就关掉它(inject 自己的 IPC 命令,对已注入的
        #   keystore2 生效,不是改配置文件——下次 keystore2 重启、inject 重新注入后要再关一次)。
        if "$RBIN/inject" --webui-set-auto-targets 0 >> "$LOG/inject.boot.log" 2>&1; then
            log "✓ 已关闭 inject 自动目标发现(不再监听 packages.list / 遍历 /data/app)"
        else
            log "✗ 关闭自动目标发现失败(见 inject.boot.log),自动目标发现可能仍在跑,可能被检测器当成 KernelSU"
        fi
        sleep 5
    else
        fails=$((fails+1)); rm -f "$STATE/.hook_ok"
        if [ "$fails" -le 4 ]; then
            log "✗ hook 未 commit(Bug C,fails=$fails),kill keystore2 pid=$pid 让它干净重启重注"
            kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
            sleep 4                  # 等 keystore2 重启并完全就绪
        else
            log "✗ hook 连续 $fails 次未 commit,退避 30s 避免 keystore2 抖动"
            sleep 30; fails=0
        fi
    fi
  done ) &

# ---- P2.0:system_server 注入(应用列表隐藏,实验,默认不注入)----
# 注入 system_server 风险远高于 keystore2:出错=开机即崩。所以:
#   ① 默认关,靠一次性开关触发:adb shell touch /data/local/tmp/herald_ss_inject,然后 reboot;
#   ② 开机时见到标志就先删掉它(消费),再注入一次——这样即便本次把 system_server 搞崩/重启,
#      下次开机已无标志、不再注入,自动恢复干净,不会 bootloop;
#   ③ 绝不 kill system_server(kill 它=重启);注入失败就保持原样(P2.0 的扩展是纯透传,无副作用)。
SS_FLAG=/data/local/tmp/herald_ss_inject
if [ -f "$SS_FLAG" ]; then
    rm -f "$SS_FLAG"
    ( for _ in 1 2 3 4 5 6; do pidof system_server >/dev/null 2>&1 && break; sleep 2; done
      sspid=$(pidof system_server 2>/dev/null)
      if [ -n "$sspid" ]; then
          sleep 8   # 等 system_server 把系统服务都注册完再注入
          log "注入 system_server pid=$sspid(inject --target system_server,实验;一次性标志已消费)"
          "$RBIN/inject" --target system_server >> "$LOG/inject.ss.boot.log" 2>&1
          rc=$?
          if [ "$rc" = 0 ] && grep -qi "injection completed" "$LOG/inject.ss.boot.log" 2>/dev/null; then
              log "✓ system_server 注入返回成功 pid=$sspid(稳定性看真机;透传扩展应不改变任何行为)"
          else
              log "✗ system_server 注入未成功(rc=$rc,见 inject.ss.boot.log);system_server 未被 kill、保持原样"
          fi
      else
          log "✗ 没等到 system_server 就绪,跳过本次注入"
      fi ) &
fi

# ---- keybox 自愈:只要当前 keybox 不是 valid+未吊销,就想办法换一张能用的(用户要求 2026-11)----
#   ★真机验证发现:CSR 常被原生工作进程拒绝(v2、v1-native 都拒过,status 还不一样),而且设备上同一时间
#   还有一张之前成功下发、没过期也没被吊销的 keybox(真机 ec 证书链只约 12 天有效期)——像是已有一张有效
#   证书时,再请求新的会被拒。反复重试大概率白费请求、也可能被下发端当滥用。
#   ★用户点破了关键:哪张 keybox 不重要,能用、没被吊销就行,我们本来就能直接装一份——不一定非要等
#   Google 现场签发。所以策略改成:
#     1. 当前 keybox valid 且没被吊销 → 什么都不做(不管多久没检查过,反复下发/导入本身有代价,不值当)。
#     2. 否则:先试一次 live 下发(rkp_issue v2)+ 导入,成功最好;
#     3. live 下发失败 → 退回"自愈":把镜像里烤的 seed/keybox.xml(bundled)重新装一遍,好歹不让设备
#        停在"没有可用 keybox"的状态。bundled 这把若本身也被吊销,这步救不了,得用户自己换一份新的
#        keybox.xml(heraldctl keybox import)。
#   检查间隔用失败计数做退避,别一直按固定间隔硬敲;keybox 已经 valid 时按 30 分钟间隔的"闲置"节奏查,
#   不会真的下发/导入,所以这个间隔本身不敏感。只在 keystore2 活着才动。
#   ★2026-11 曾经加过"伪装状态门控"(怀疑现场 RKP 在设备被全局伪装成 Pixel 时会被 vendor TEE 拒绝,
#   -18/-20),后来用户用 V97(resetprop 式伪装)、以及把现在的引擎二进制换到 V97 版本后两次真机对比
#   实验,证实伪装状态本身跟 RKP 成败无关——V97 全局伪装成 Pixel、重启生效后现场 RKP 照样成功,Play
#   认证也过了。真正卡住的是 device-spoof 的 build 模式(build.prop 文件本身被真的改写成 Pixel),
#   跟是否伪装、用哪颗引擎都无关,具体卡在哪一层还没查清楚。身份门控这个假设被证伪,已经撤掉。
RKP_FAILS=$CFG/data/.rkp_fail_count
( while true; do
    fails=$(cat "$RKP_FAILS" 2>/dev/null); case $fails in ''|*[!0-9]*) fails=0 ;; esac
    if [ "$fails" -eq 0 ]; then sleep 1800                 # 没失败过(或刚自愈成功):正常节奏,30 分钟查一次
    elif [ "$fails" -lt 5 ]; then sleep 60                 # 刚开始失败:先快速重试几次(最多 5 分钟)
    elif [ "$fails" -ge 20 ]; then sleep 86400             # 一直失败:退到一天查一次(大概率 bundled 那把也不能用了,等用户换新的)
    else sleep 3600; fi                                    # 失败够多次:退到一小时查一次
    pidof keystore2 >/dev/null 2>&1 || continue

    rkp_state=$("$RBIN/keymint" --webui-get-keybox-state 2>&1)
    echo "$rkp_state" | grep -qF '"valid":true' || rkp_bad=1
    rkp_revoc_out=$("$RBIN/keymint" --webui-check-keybox-revocation 2>&1)
    echo "$rkp_revoc_out" | grep -qi 'revoked' && rkp_bad=1
    if [ -z "$rkp_bad" ]; then
        echo 0 > "$RKP_FAILS" 2>/dev/null; continue   # 当前这把能用,不动它
    fi
    unset rkp_bad
    log "当前 keybox 不是 valid+未吊销($rkp_state / revocation=$rkp_revoc_out),尝试换一张"

    "$RBIN/keymint" --webui-rkp-list > "$W/rkp_before" 2>/dev/null
    # V63 真机实测:本机只有 v2(和默认的 auto)能用,v1/v1-native 会报错;auto 不稳定(实测会落到 v1-native
    #   上报错),这里直接写死 v2,不依赖 auto 的选择(doc/herald-backend-api.md)
    rkp_issue_out=$("$RBIN/keymint" --webui-rkp-issue --confirm-issuance v2 2>&1)
    rkp_ok=
    if echo "$rkp_issue_out" | grep -qi '^err'; then
        log "✗ RKP live 下发失败:$rkp_issue_out"
    else
        sleep 2   # 等结果落进 rkp-artifacts,下一次 rkp list 才看得到
        "$RBIN/keymint" --webui-rkp-list > "$W/rkp_after" 2>/dev/null
        rkp_new=$(grep -Fxv -f "$W/rkp_before" "$W/rkp_after" 2>/dev/null)   # rkp_after 里不在 rkp_before 的行(不用 diff,怕精简镜像没带)
        rkp_id=$(echo "$rkp_new" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | tail -1)             # 带引号的 "id":"xxx"
        [ -z "$rkp_id" ] && rkp_id=$(echo "$rkp_new" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | tail -1)   # 不带引号的 "id":123
        [ -z "$rkp_id" ] && rkp_id=$(echo "$rkp_new" | tail -1)                                 # 两种都没抽到,把整行当 id
        if [ -z "$rkp_id" ]; then
            log "✗ RKP 已下发但从 rkp list 认不出新结果的 id,没法导入(手动用 heraldctl rkp list/import):$rkp_issue_out"
        else
            rkp_import_out=$("$RBIN/keymint" --webui-rkp-import "$rkp_id" --confirm-replace 2>&1)
            if echo "$rkp_import_out" | grep -qi '^err'; then
                log "✗ RKP 导入失败(id=$rkp_id):$rkp_import_out"
            else
                log "✓ RKP live 下发+导入成功(id=$rkp_id)"; rkp_ok=1
            fi
        fi
    fi
    rm -f "$W/rkp_before" "$W/rkp_after"

    if [ -z "$rkp_ok" ]; then
        # live 下发没成,退回自愈:重装镜像里烤的 bundled keybox,至少不留在"没有可用 keybox"的状态
        rkp_seed_b64=$(base64 "$SEED/keybox.xml" 2>/dev/null | tr -d '\r\n')
        if [ -n "$rkp_seed_b64" ] && rkp_seed_out=$("$RBIN/keymint" --webui-install-keybox "$rkp_seed_b64" 2>&1) \
           && ! echo "$rkp_seed_out" | grep -qi '^err'; then
            log "✓ 已回退重装 bundled keybox(seed/keybox.xml):$rkp_seed_out"; rkp_ok=1
        else
            log "✗ 回退重装 bundled keybox 也失败:${rkp_seed_out:-读不到 $SEED/keybox.xml}"
        fi
    fi

    if [ -n "$rkp_ok" ]; then echo 0 > "$RKP_FAILS" 2>/dev/null
    else fails=$((fails + 1)); echo "$fails" > "$RKP_FAILS" 2>/dev/null; fi
  done ) &

# 注:全局 PIF(build 指纹)+ boot-state(green/locked)已由 post-fs-data 的 herald-global-pif.sh 统一在
#     zygote 之前用 resetprop 全局应用(见 init.herald.rc / herald-global-pif.sh),此处不再重复。
# ---- V30 boot-state 伪装(锁态/绿,运行时读、非冻结属性,不需要赶 zygote,挪出 post-fs-data 临界窗口)----
# 对照 OMK 原版 service.sh 本来就在 late service(sleep 20 后)跑这块,不在 post-fs-data —— 之前 V29
# 把它也塞进 post-fs-data 是多余的风险(诊断见 herald-global-pif.sh 头注释)。同 ENABLE_FLAG 门控(默认关,
# 与 build 身份伪装一致开关);固定值,非 profile 驱动。
BOOTSTATE_RESETPROP=$BIN/resetprop
if [ -x "$BOOTSTATE_RESETPROP" ]; then
  ( sleep 20
    [ -f "$ENABLE_FLAG" ] || { log "全局伪装未开启,跳过 boot-state 覆写"; exit 0; }
    rpm() { "$BOOTSTATE_RESETPROP" -n "$1" "$2" 2>/dev/null; }
    rpm ro.boot.verifiedbootstate green
    rpm ro.boot.vbmeta.device_state locked
    rpm ro.boot.flash.locked 1
    rpm ro.boot.veritymode enforcing
    rpm vendor.boot.verifiedbootstate green
    rpm vendor.boot.vbmeta.device_state locked
    rpm ro.secureboot.lockstate locked
    rpm sys.oem_unlock_allowed 0
    rpm ro.boot.warranty_bit 0
    rpm ro.warranty_bit 0
    rpm ro.vendor.warranty_bit 0
    rpm ro.vendor.boot.warranty_bit 0
    rpm ro.debuggable 0
    rpm ro.force.debuggable 0
    rpm ro.secure 1
    rpm ro.adb.secure 1
    log "boot-state 覆写完成(全局伪装已开启)"
  ) &
fi
}
HERALDP_START="$HERALDP_START heraldp_start_attestation"
# 两个只读的慢 list 命令后台执行,不阻塞主循环(需 herald-core V1.4+ 的 HERALDP_ASYNC;旧 broker 忽略此变量,照常内联)。
# rkp_list 要联网拉远程配置目录,最慢;list(内建机型)其次。都是只读,可并发。
HERALDP_ASYNC="$HERALDP_ASYNC list rkp_list"

# V64:跑 keymint --webui-*,退出码非 0 时第一行加 "err <命令> rc=N",后面保留 keymint 自己的报错原文
#   (V63 只看输出文字,失败也是退出码 0;patch 失败时还把原文丢了,只剩 err patch-failed)
herald_km() {   # $1 = 命令名,其余 = keymint 参数
  _kn=$1; shift
  "$RBIN/keymint" "$@" > "$W/herald_km" 2>&1 </dev/null; _krc=$?
  # V65:list/apply 要现下 PIF 目录,网不稳时偶发 "unexpected end of file";这两条没有副作用,自动重试 2 次
  #   (rkp_issue 会真的签发,不自动重试)
  _kt=0
  while [ "$_krc" != 0 ] && [ $_kt -lt 2 ] && { [ "$_kn" = list ] || [ "$_kn" = apply ]; } \
        && grep -q 'unexpected end of file' "$W/herald_km" 2>/dev/null; do
    _kt=$((_kt + 1)); sleep 2
    "$RBIN/keymint" "$@" > "$W/herald_km" 2>&1 </dev/null; _krc=$?
  done
  _ks=""; [ $_kt -gt 0 ] && _ks=" (已重试 $_kt 次)"
  [ "$_krc" = 0 ] || echo "err $_kn rc=$_krc$_ks"
  cat "$W/herald_km" 2>/dev/null; rm -f "$W/herald_km"
  return $_krc
}
# V64 安全补丁同步:先交给 keymint;它拒绝时自己改(V63 实测 keymint 对任何日期都失败)。
#   自己改三处:config.toml [trust] 的 security_patch(keymint 每次开机把两个 security_patch 属性同步成它)、
#   伪装 profile 的 security_patch(重启后全局属性层用它)、全局伪装开着时当场 resetprop 两个属性。
#   os/vendor/boot_patchlevel 不动:那是 TEE 给密钥绑定的补丁级别,改低会让已有密钥失效。
# V74:`patch <日期|auto> all` 连 config.toml [trust] 的 os/vendor/boot_patchlevel 一起改(默认不动)。
#   那三项是 TEE 给密钥绑定的补丁级别:改低之后,用更高级别生成的现有密钥会被拒绝用(要重新生成)。
#   关全局伪装想把三项也还原成真机值时用:`heraldctl raw patch 2025-05-05 all`。
herald_patch_all_levels() {   # $1 = 日期
  _cf=$CFG/config.toml
  [ -f "$_cf" ] || { echo "err patch all: 没有 $_cf"; return 1; }
  sed -e '/^\[trust\]/,/^\[/ s/^os_patchlevel = "[^"]*"/os_patchlevel = "'"$1"'"/' \
      -e '/^\[trust\]/,/^\[/ s/^vendor_patchlevel = "[^"]*"/vendor_patchlevel = "'"$1"'"/' \
      -e '/^\[trust\]/,/^\[/ s/^boot_patchlevel = "[^"]*"/boot_patchlevel = "'"$1"'"/' "$_cf" > "$W/herald_cf" 2>/dev/null
  if grep -q "^os_patchlevel = \"$1\"" "$W/herald_cf" && grep -q "^vendor_patchlevel = \"$1\"" "$W/herald_cf" && grep -q "^boot_patchlevel = \"$1\"" "$W/herald_cf"; then
    cat "$W/herald_cf" > "$_cf"; rm -f "$W/herald_cf"
    echo "os/vendor/boot_patchlevel 也已改为 $1(重启生效;用更高补丁级别生成的现有密钥可能不能再用,需要重新生成)"
  else rm -f "$W/herald_cf"; echo "err patch all: config.toml 的 [trust] 里 os/vendor/boot_patchlevel 没改成"; return 1; fi
}
# spoof/app-spoof:按 App 伪装模式(模块装了且 spoof_mode 不是 global)。这个模式下系统属性一律保持真机值:
#   config.toml [trust] 的 security_patch 固定为真机日期(keymint 启动时按它同步全局 security_patch 属性,
#   所以属性 = 真机 = /system/build.prop,Hunter 不报不一致);os/vendor/boot_patchlevel(TEE 认证里的补丁级别)
#   照常跟 profile 日期走;名单里的 App 由 framework 钩子看到 profile 的 Build.VERSION.SECURITY_PATCH。
herald_app_spoof_on() {
  [ -f /system/etc/herald_payload/app-spoof/targets.default ] && [ "$(cat "$CFG/data/spoof_mode" 2>/dev/null)" != global ]
}
herald_cfg_secpatch() {   # config.toml [trust] 的 security_patch 改成 $1
  _cf=$CFG/config.toml
  [ -f "$_cf" ] || return 1
  sed '/^\[trust\]/,/^\[/ s/^security_patch = "[^"]*"/security_patch = "'"$1"'"/' "$_cf" > "$W/herald_cf2" 2>/dev/null
  grep -q "^security_patch = \"$1\"" "$W/herald_cf2" 2>/dev/null || { rm -f "$W/herald_cf2"; return 1; }
  cat "$W/herald_cf2" > "$_cf"; rm -f "$W/herald_cf2"
}
herald_spoof_patch_sync() {   # 切换模式后(伪装开着)按新模式重排四个补丁级别,app-spoof 插件的 spoof_mode 调用
  _sd=$(sed -n 's/.*"security_patch":"\([^"]*\)".*/\1/p' "$DATA_PIF" 2>/dev/null | head -1)
  [ -n "$_sd" ] || { echo "err 当前 profile 里没有 security_patch"; return 1; }
  herald_patch "$_sd all"
}
herald_real_patch() {   # 真机的安全补丁日期:原厂 vendor 的 build.prop 文件(不受 resetprop 影响)
  sed -n 's/^ro\.vendor\.build\.security_patch=//p' /vendor/build.prop 2>/dev/null | head -1 | tr -d '\r'
}
herald_patch() {   # $1 = auto | YYYY-MM-DD [all]
  _all=0; case "$1" in *" all") _all=1; set -- "${1% all}" ;; esac
  herald_patch_core "$1" || return 1
  [ $_all = 1 ] || return 0
  herald_patch_all_levels "$_pd"
}
herald_patch_core() {   # $1 = auto | YYYY-MM-DD
  _pd=$1
  if [ "$_pd" = auto ]; then
    _pd=$(sed -n 's/.*"security_patch":"\([^"]*\)".*/\1/p' "$DATA_PIF" 2>/dev/null | head -1)
    [ -n "$_pd" ] || { echo "err patch auto: 当前伪装 profile 里没有 security_patch,请直接给日期"; return 1; }
  fi
  case "$_pd" in
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
    *) echo "err patch 日期要写成 YYYY-MM-DD 或 auto: $1"; return 1 ;;
  esac
  _today=$(date +%Y-%m-%d)
  if [ "$(echo "$_pd" | tr -d -)" -gt "$(echo "$_today" | tr -d -)" ]; then
    echo "err patch 日期不能晚于今天($_today): $_pd"; return 1
  fi
  if herald_app_spoof_on; then
    # 按 App 伪装:profile 记新日期(名单里的 App 看到它);全局 security_patch 保持真机,不调 keymint 的同步(它会 resetprop 全局属性)
    _rp=$(herald_real_patch)
    [ -n "$_rp" ] && herald_cfg_secpatch "$_rp"
    if [ -f "$DATA_PIF" ]; then
      sed 's/"security_patch":"[^"]*"/"security_patch":"'"$_pd"'"/' "$DATA_PIF" > "$W/herald_cf" && cat "$W/herald_cf" > "$DATA_PIF"
      rm -f "$W/herald_cf"
    fi
    echo "ok patch $_pd via=app-spoof reboot-required"
    echo "按 App 伪装模式:名单里的 App 看到 $_pd;全局 security_patch 属性保持真机 ${_rp:-?}(config.toml 的 security_patch 也是它);带 all 时 TEE 的 os/vendor/boot_patchlevel 改成 $_pd"
    return 0
  fi
  if "$RBIN/keymint" --webui-sync-security-patch "$1" > "$W/herald_t5" 2>&1 </dev/null; then
    echo "ok patch $_pd via=keymint reboot-required"; cat "$W/herald_t5"; rm -f "$W/herald_t5"; return 0
  fi
  _why=$(head -c 400 "$W/herald_t5" 2>/dev/null | tr '\n' ' '); rm -f "$W/herald_t5"
  _cf=$CFG/config.toml
  [ -f "$_cf" ] || { echo "err patch keymint 拒绝且没有 $_cf: $_why"; return 1; }
  sed '/^\[trust\]/,/^\[/ s/^security_patch = "[^"]*"/security_patch = "'"$_pd"'"/' "$_cf" > "$W/herald_cf" 2>/dev/null
  if ! grep -q "^security_patch = \"$_pd\"" "$W/herald_cf" 2>/dev/null; then
    rm -f "$W/herald_cf"; echo "err patch keymint 拒绝,config.toml 的 [trust] 里也没有 security_patch: $_why"; return 1
  fi
  cat "$W/herald_cf" > "$_cf"; rm -f "$W/herald_cf"          # 原地写,保留属主/权限/SELinux 标签
  if [ -f "$DATA_PIF" ]; then
    sed 's/"security_patch":"[^"]*"/"security_patch":"'"$_pd"'"/' "$DATA_PIF" > "$W/herald_cf" && cat "$W/herald_cf" > "$DATA_PIF"
    rm -f "$W/herald_cf"
  fi
  _now=""
  if [ -f "$ENABLE_FLAG" ] && [ -x "$BIN/resetprop" ]; then
    "$BIN/resetprop" -n ro.build.version.security_patch "$_pd" 2>/dev/null
    "$BIN/resetprop" -n ro.vendor.build.security_patch "$_pd" 2>/dev/null
    _now=" 属性已当场改"
  fi
  echo "ok patch $_pd via=backend reboot-required$_now"
  echo "keymint 自己同步失败,已由后端改 config.toml 的 security_patch 和伪装 profile(TEE 补丁级别不变)。keymint 原话: $_why"
}

# ---- 命令:指纹伪装 / keybox / RKP ----
  # ---- 指纹伪装(build 身份,全局层;native 与 TEE attestation 共读同一 pif_fingerprint.json,
  #       V30 已端到端验证两层一致——custom 导入直写此文件已足够,不强求都走 apply-pif-fingerprint)
  # ★V36:get 附加我们自己的 global_pif_enabled 开关状态——keymint 的 "enabled:true" 是它自己的
  #   内部记录(选过哪个 profile),跟是否真的全局 resetprop 覆写是两个独立开关(V31 诊断坐实这个
  #   混淆会误导用户),App 要把两者分开显示,靠这行附加标记区分。
heraldp_cmdf_get() {
  arg=$1
      "$RBIN/keymint" --webui-get-pif-fingerprint-state > "$resp" 2>/dev/null \
                || cp -f "$DATA_PIF" "$resp" 2>/dev/null || echo "err no-profile" > "$resp"
              # V67:keymint 的输出或回落的 profile 文件末尾可能没有换行,标记行会粘在 JSON 的 } 后面
              #   (`{…}HERALD_GLOBAL_PIF_FLAG=off`),前端按行找就找不到。接口约定是"末尾单独一行",这里保证它。
              [ -n "$(tail -c1 "$resp" 2>/dev/null)" ] && echo >> "$resp"
              # V72:keymint 把 JSON 里的 "/" 转义成 "\/"(合法但少见),前端按原样显示/比较会出问题;还原成 "/"。
              #   `spoof set` 的输入不受影响(\/ 和 / 在 JSON 里等价)。
              sed 's#\\/#/#g' "$resp" > "$resp.u" 2>/dev/null && mv -f "$resp.u" "$resp"
              if [ -f "$ENABLE_FLAG" ]; then echo "HERALD_GLOBAL_PIF_FLAG=on" >> "$resp"
              else echo "HERALD_GLOBAL_PIF_FLAG=off" >> "$resp"; fi
}
  # ★V36:set 是唯一真正的"提交点"(不管来源是内建目录预填后编辑过的表单,还是自定义/文件导入),
  #   诚实校验(GLOBAL_SPOOF_WILL_APPLY/FALLBACK)从 apply 挪到这里统一做——之前挂在 apply 上,
  #   但 apply 现在只是"预填表单"的中间步骤,不代表用户已经确认提交,校验挂错位置会在用户编辑表单
  #   之前就提前判定、文案对不上。
heraldp_cmdf_set() {
  arg=$1
      if [ -f "$W/herald_profile_in" ] && grep -q '"fingerprint"' "$W/herald_profile_in" 2>/dev/null; then
                cp -f "$W/herald_profile_in" "$DATA_PIF" && chown 1017:1017 "$DATA_PIF" && chmod 0600 "$DATA_PIF"
                # 安全补丁:认证层(TEE attestation)同步,与全局 props(global-pif 从本 profile 设)一致
                sp=$(sed -n 's/.*"security_patch":"\([^"]*\)".*/\1/p' "$W/herald_profile_in" | head -1)
                rm -f "$W/herald_profile_in"
                # V81:连 os/vendor/boot_patchlevel 一起同步(V80 真机:开伪装只同步了 security_patch,四个补丁级别对不上)
                _pr=""; [ -n "$sp" ] && _pr=$(herald_patch "$sp all" 2>&1 | head -1)
                : > "$ENABLE_FLAG"; chown 1017:1017 "$ENABLE_FLAG" 2>/dev/null   # 显式打开全局伪装(默认关)
                _rel=$(sed -n 's/.*"release":"\([^"]*\)".*/\1/p' "$DATA_PIF" 2>/dev/null | head -1)
                # V105:目录机型(spoof apply)写的 profile 常无独立 "release" 字段——release 在
                # fingerprint 串里(brand/product/device:RELEASE/id/incr:type/tags)。herald-global-pif.sh
                # 的 valid_profile 开机时就是这么从 fingerprint 现推的;这里不推就会对 panther_beta 这类
                # 本来会正常应用的 profile 谎报 WILL_FALLBACK(用户实测被误导)。空就从 fingerprint 推,对齐开机脚本。
                if [ -z "$_rel" ]; then
                  _fp=$(sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p' "$DATA_PIF" 2>/dev/null | head -1 | sed 's#\\/#/#g')
                  _rel=$(echo "$_fp" | cut -d: -f2- | cut -d/ -f1)
                fi
                # ★用户明确要求允许 CANARY/beta release(2026-10-29:"原来就是那么实现的,说明是可以
                # 这么做的"——最初验证过能过认证的那套配置[panther_beta]本来就是 CANARY)。跟
                # herald-global-pif.sh 的 valid_profile() 同步放宽:只要 release 非空就算 WILL_APPLY,
                # 不再按"是否纯数字"拒绝。只有真空值才会被 global-pif 回落,这里对应报 FALLBACK。
                case "$_rel" in
                  "")
                    # ★实测坐实(用户 2026-10-29 复现):只说"回落默认指纹"太模糊,不知道回落成了什么——
                    # 读出 /system seed 具体是哪个机型,点名说清楚(不是你选的、也不是设备原本的 TB321FU,
                    # 是第三个值:我们烤入的默认兜底)。
                    _fbmodel=$(sed -n 's/.*"model":"\([^"]*\)".*/\1/p' "$SEED/pif_fingerprint.json" 2>/dev/null | head -1)
                    _fbfp=$(sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p' "$SEED/pif_fingerprint.json" 2>/dev/null | head -1)
                    # 各自独占一行(不是空格分隔)——fallback_model 可能带空格(如 "Pixel 7"),按行取才不会被截断。
                    printf 'ok set GLOBAL_SPOOF_WILL_FALLBACK release=%s\nfallback_fingerprint=%s\nfallback_model=%s\n' \
                      "$_rel" "$_fbfp" "$_fbmodel" > "$resp" ;;
                  *)            echo "ok set GLOBAL_SPOOF_WILL_APPLY release=$_rel(重启后全局生效,reboot-required)" > "$resp" ;;
                esac
                [ -n "$_pr" ] && echo "security_patch: $_pr" >> "$resp"
              else echo "err invalid-profile" > "$resp"; fi
}
heraldp_cmdf_disable() {
  arg=$1
      rm -f "$ENABLE_FLAG"
              "$RBIN/keymint" --webui-disable-pif-fingerprint >/dev/null 2>&1
              # V81:四个补丁级别同步回真机日期(V80 真机:关伪装后一个都不同步)。真机日期从 /vendor/build.prop 文件读
              #   (属性可能被本轮伪装改过,文件不会)。伪装 profile 里的日期保留,下次开伪装还用它。
              _rp=$(herald_real_patch)
              if [ -n "$_rp" ]; then
                [ -f "$DATA_PIF" ] && cp -f "$DATA_PIF" "$W/herald_pif_keep"
                _pr=$(herald_patch "$_rp all" 2>&1 | head -1)
                [ -f "$W/herald_pif_keep" ] && { cat "$W/herald_pif_keep" > "$DATA_PIF"; rm -f "$W/herald_pif_keep"; }
              else _pr="err 读不到真机补丁日期(/vendor/build.prop 的 ro.vendor.build.security_patch)"; fi
              { echo "ok disabled reboot-required(属性层本轮已覆写的值要重启才还原)"; echo "security_patch: $_pr"; } > "$resp"
}
heraldp_cmdf_patch() {
  arg=$1
      herald_patch "$arg" > "$resp" 2>&1
}
heraldp_cmdf_list() {
  arg=$1
      herald_km list --webui-list-pif-devices > "$resp"
}
  # ★V36:apply 现在只是"用内建目录某条把完整 profile 预填进 pif_fingerprint.json"的中间步骤,
  #   不再代表用户确认提交——不碰 ENABLE_FLAG、不做诚实校验(那是 set 的事)。App 拿到 apply 的
  #   结果后会紧接着调一次 get 把完整字段读回来填进可编辑表单,用户看过/改过再点"保存并应用"才
  #   真正走到上面的 set。
heraldp_cmdf_apply() {
  arg=$1
      herald_km apply --webui-apply-pif-fingerprint $arg > "$resp"
}

# ---- Keybox 完整控制:导出/导入/状态/吊销检查(直接对应 keymint --webui-* 用法字符串)----
heraldp_cmdf_keybox_export() {
  arg=$1
      cp -f "$DATA_KEYBOX" "$resp" 2>/dev/null || echo "err no-keybox" > "$resp"
}
heraldp_cmdf_keybox_import() {
  arg=$1
      if [ -f "$W/herald_keybox_b64_in" ]; then
                            b64=$(cat "$W/herald_keybox_b64_in" 2>/dev/null); rm -f "$W/herald_keybox_b64_in"
                            herald_km keybox_import --webui-install-keybox "$b64" > "$resp"
                          else echo "err no-payload" > "$resp"; fi
}
heraldp_cmdf_keybox_state() {
  arg=$1
      herald_km keybox_state --webui-get-keybox-state > "$resp"
}
heraldp_cmdf_keybox_inspector() {
  arg=$1
      herald_km keybox_inspector --webui-get-keybox-inspector > "$resp"
}
heraldp_cmdf_keybox_revocation() {
  arg=$1
      herald_km keybox_revocation --webui-check-keybox-revocation > "$resp"
}
heraldp_cmdf_rkp_issue() {
  arg=${1:-v2}   # V63 真机实测:本机只有 v2(和默认的 auto)能用,v1/v1-native 会报错;auto 不稳定,不传参数时直接当 v2
      herald_km rkp_issue --webui-rkp-issue --confirm-issuance $arg > "$resp"
}
heraldp_cmdf_rkp_list() {
  arg=$1
      herald_km rkp_list --webui-rkp-list > "$resp"
}
heraldp_cmdf_rkp_import() {
  arg=$1
      if [ -z "$arg" ]; then echo "err rkp_import 缺少结果 id(先 rkp list 查)" > "$resp"
                  else herald_km rkp_import --webui-rkp-import $arg --confirm-replace > "$resp"; fi
}

# ---- inject 的自动目标发现:诊断/手动开关(默认开机已自动关,见上面的注入守护循环)----
heraldp_cmdf_auto_targets_get() {
  arg=$1
      "$RBIN/inject" --webui-get-auto-targets > "$resp" 2>&1
}
heraldp_cmdf_auto_targets_set() {
  arg=$1
      case "$arg" in
        0|1) "$RBIN/inject" --webui-set-auto-targets "$arg" > "$resp" 2>&1 ;;
        *)   echo "err auto_targets_set 参数须是 0 或 1" > "$resp" ;;
      esac
}

# selftest / diag 的引擎部分
herald_selftest_attestation() { [ -x "$RBIN/keymint" ] && echo "keymint=present" || echo "keymint=MISSING"; }
herald_diag_attestation() {
              echo "== 属性"
                for _k in ro.product.model ro.product.brand ro.product.manufacturer ro.build.fingerprint ro.build.version.release ro.build.version.security_patch ro.vendor.build.security_patch ro.tb321fu.mod_version vendor.camera.aux.packagelist; do
                  echo "$_k=$(getprop $_k 2>/dev/null)"; done
                echo "== 全局伪装"
                [ -f "$CFG/data/global_pif_enabled" ] && echo "flag=on" || echo "flag=off"
                herald_app_spoof_on && echo "mode=app" || echo "mode=global"
                ls -lZ /data/system/imitation.conf 2>&1
                ls -l "$CFG/data/pif_fingerprint.json" 2>&1
                grep -E '^(security_patch|os_patchlevel|vendor_patchlevel|boot_patchlevel)' "$CFG/config.toml" 2>&1
                for _f in logs/global-pif.log logs/keymint.log; do
                  echo "== $_f (末 25 行)"; tail -n 25 "$CFG/$_f" 2>&1; done
                echo "== keymint.boot.log (末 12 行)"; tail -n 12 "$LOG/keymint.boot.log" 2>&1
                echo "== keybox 自愈"
                _fails=$(cat "$CFG/data/.rkp_fail_count" 2>/dev/null); case $_fails in ''|*[!0-9]*) _fails=0 ;; esac
                echo "连续失败次数:$_fails(0 = 上次查的时候当前 keybox 是 valid+未吊销,没动它)"
                echo "开机至今:$(( $(cut -d. -f1 /proc/uptime 2>/dev/null) / 60 )) 分钟(刚开机、还没失败过时按 30 分钟节奏查)"
                echo "keybox state: $("$RBIN/keymint" --webui-get-keybox-state 2>&1)"
                echo "keybox revocation: $("$RBIN/keymint" --webui-check-keybox-revocation 2>&1)"
                echo "rkp list: $("$RBIN/keymint" --webui-rkp-list 2>&1)"
                echo "== herald-start.log 里 RKP/keybox 相关的最后 20 行"
                grep -iE 'rkp|keybox' "$HERALDLOG_META/herald-start.log" 2>/dev/null | tail -n 20
}
HERALDP_SELFTEST="$HERALDP_SELFTEST herald_selftest_attestation"
HERALDP_DIAG="$HERALDP_DIAG herald_diag_attestation"
# 附带数据:spoof set 的 profile JSON、keybox import 的 base64
HERALDP_ATTACH="$HERALDP_ATTACH set:herald_profile_in:raw keybox_import:herald_keybox_b64_in:b64"
