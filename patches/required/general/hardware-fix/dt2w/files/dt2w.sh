# dt2w 的 broker 插件(装在 /system/etc/herald_payload/plugins/dt2w.sh,由 herald-start.sh source)。
# 提供 broker 命令 dt2w on|off|status,开机做一次初始化,空闲时每 5 秒按设置同步一次。用到 herald_sys、blog、$W。
#
# 双击唤醒(TB321FU,Novatek 触摸)
#   硬件/驱动本来就支持:往 /proc/gesture_control 写 1,灭屏后双击屏幕,驱动上报 KEY_WAKEUP,系统亮屏。
#   原厂由 ZUI 设置经 vendor.lenovo.hardware.touchscreen HAL 写这个节点;GSI 里没有调用方,所以一直是 0。
#   Pixel 自带 显示 → 点按唤醒(Secure.double_tap_to_wake),但走的是 PowerManager → Power HAL setMode(DOUBLE_TAP_TO_WAKE),
#   高通 Power HAL 不实现这个模式;而且 GSI 的 config_supportDoubleTapWake=false,开关本身是隐藏的。
#   所以本插件:
#     1. 开机用 fabricated overlay 把 android:bool/config_supportDoubleTapWake 打成 true,让 Pixel 设置里显示 “点按唤醒”;
#        (不需要另做 RRO APK;fabricated overlay 存在 /data,只在缺失/被关时重建)
#     2. 以 Secure.double_tap_to_wake 为唯一开关(没设过 = 系统默认 1 = 开),同步到 /proc/gesture_control。
#   节点标签是通用 proc,只有 herald(permissive)和联想 touchscreen HAL 写得进;init/vendor_init 都没有 proc 写权限,
#   所以放在 broker 里做,不用改 sepolicy。
DT2W_NODE=/proc/gesture_control
DT2W_OVL_NAME=tb321fu_dt2w
DT2W_RES=android:bool/config_supportDoubleTapWake

herald_dt2w_want() {   # 用户在设置里的选择:0 关,其余(1/没设过)开
  _dv=$(herald_sys /system/bin/settings get secure double_tap_to_wake | tr -d '\r\n ')
  case "$_dv" in 0) echo 0 ;; *) echo 1 ;; esac
}
herald_dt2w_cur() { tr -d '\r\n ' < "$DT2W_NODE" 2>/dev/null; }
herald_dt2w_apply() {  # $1 = 0|1;节点值不同才写。返回 0 = 节点现在是 $1
  [ -e "$DT2W_NODE" ] || return 1
  [ "$(herald_dt2w_cur)" = "$1" ] && return 0
  echo "$1" > "$DT2W_NODE" 2>/dev/null
  _dc=$(herald_dt2w_cur)
  blog "dt2w: gesture_control -> $1 (读回 ${_dc:-?})"
  [ "$_dc" = "$1" ]
}
herald_dt2w_ovl_state() {   # 设 $_ds = on | off | missing,$_dovl = 完整 overlay 标识(如 com.android.shell:tb321fu_dt2w)
  # 不用 $(...) 调:变量要留在当前 shell
  herald_sys /system/bin/cmd overlay list --user 0 android > "$W/herald_t12"
  _dl=$(grep -m1 ":$DT2W_OVL_NAME\$" "$W/herald_t12"); rm -f "$W/herald_t12"
  _dovl=$(echo "$_dl" | sed 's/^.*\] *//')
  case "$_dl" in "") _ds=missing ;; *"[x]"*) _ds=on ;; *) _ds=off ;; esac
}
herald_dt2w_cfg() { herald_sys /system/bin/cmd overlay lookup android "$DT2W_RES" | tr -d '\r\n '; }   # 当前生效值 true/false
herald_dt2w_ovl_ensure() {   # 结果在 $_ds
  herald_dt2w_ovl_state
  [ "$_ds" = on ] && return 0
  # 镜像里已有静态 RRO 把它设成 true(推荐做法,见 README)就不用 fabricated overlay:
  #   fabricated overlay 实测重启后会被系统删掉(2026-11-09 test-v1.8),每次开机重建会让所有进程收到一次资源变更
  if [ "$(herald_dt2w_cfg)" = true ]; then _ds=static; return 0; fi
  if [ "$_ds" = missing ]; then
    herald_sys /system/bin/cmd overlay fabricate --target android --name "$DT2W_OVL_NAME" "$DT2W_RES" 0x12 0xffffffff >/dev/null
    herald_dt2w_ovl_state
    blog "dt2w: fabricate overlay -> $_ds $_dovl"
  fi
  if [ "$_ds" = off ] && [ -n "$_dovl" ]; then
    herald_sys /system/bin/cmd overlay enable --user 0 "$_dovl" >/dev/null
    herald_dt2w_ovl_state
    blog "dt2w: 启用 overlay $_dovl -> $_ds"
  fi
}
herald_dt2w_start() {
  [ -e "$DT2W_NODE" ] || { blog "dt2w: 没有 $DT2W_NODE,不是 Novatek 触摸/原厂内核,插件不做事"; return 0; }
  herald_dt2w_ovl_ensure
  _dw=$(herald_dt2w_want)
  herald_dt2w_apply "$_dw"
  blog "dt2w: 开机 overlay=$_ds 设置=$_dw 节点=$(herald_dt2w_cur)"
}
herald_dt2w_guard() {   # 每 5 秒:设置变了(设置页拨开关)或驱动把节点复位了,就重新写
  [ -e "$DT2W_NODE" ] || return 0
  herald_dt2w_apply "$(herald_dt2w_want)" >/dev/null
}
herald_dt2w_status() {
  _dw=$(herald_dt2w_want); _dc=$(herald_dt2w_cur)
  [ "$_dc" = 1 ] && echo "ok dt2w on" || echo "ok dt2w off"
  echo "setting=$(herald_sys /system/bin/settings get secure double_tap_to_wake | tr -d '\r\n ') (Secure.double_tap_to_wake; null = 默认开)"
  echo "node=$DT2W_NODE value=${_dc:-不存在}"
  herald_dt2w_ovl_state
  echo "config_supportDoubleTapWake=$(herald_dt2w_cfg) (true = 设置 → 显示 → 点按唤醒 开关可见)"
  echo "fabricated_overlay=$_ds ${_dovl:-$DT2W_OVL_NAME} (镜像带静态 RRO 时为 missing 是正常的)"
}
herald_dt2w() {
  [ -e "$DT2W_NODE" ] || { echo "err dt2w 没有 $DT2W_NODE"; return; }
  case "$1" in
    on|off)
      [ "$1" = on ] && _dw=1 || _dw=0
      herald_sys /system/bin/settings put secure double_tap_to_wake "$_dw" >/dev/null
      if [ "$(herald_dt2w_want)" = "$_dw" ] && herald_dt2w_apply "$_dw"; then echo "ok dt2w $1"
      else echo "err dt2w $1: 设置=$(herald_dt2w_want) 节点=$(herald_dt2w_cur)"; fi ;;
    status|"") herald_dt2w_status ;;
    *) echo "err dt2w 用法: dt2w on|off|status" ;;
  esac
}
herald_dt2w_diag() { echo "== dt2w"; herald_dt2w_status; }

# 注册给 broker
heraldp_cmd_dt2w() { herald_dt2w "$1"; }
HERALDP_START="${HERALDP_START:-} herald_dt2w_start"
HERALDP_IDLE="${HERALDP_IDLE:-} herald_dt2w_guard"
HERALDP_DIAG="${HERALDP_DIAG:-} herald_dt2w_diag"
