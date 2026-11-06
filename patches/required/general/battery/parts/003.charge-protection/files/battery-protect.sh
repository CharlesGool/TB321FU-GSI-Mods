# battery/charge-protection 的 broker 插件(装在 /system/etc/herald_payload/plugins/battery-protect.sh)。
# 长期插电保护:电量保持在 [min,max] 区间。写原厂的 battery/protection_setting。
#   取值(来自原厂 ZuiBatteryManagerService.setBatteryProtectedLevel):开 = 100000 + min*1000 + max,关 = 95100。
#   battery protect status | on [min max] | off     (默认 min=75 max=80)
BAT_PROT_OFF=95100
herald_bat_protect_raw() { echo $((100000 + $1 * 1000 + $2)); }
heraldp_bat_sub_protect() {
  _node=$(herald_bat_node protection)
  case "$1" in
    status|"")
      _raw=$(herald_bat_read "$_node") || { echo "err battery_protect 读不了 $_node(这台机器没有这个节点?)"; return; }
      echo "ok battery protect"
      echo "raw=$_raw"
      if herald_bat_int "$_raw" && [ "$_raw" -ge 100000 ]; then
        _r=$((_raw - 100000)); echo "protect=on"; echo "min=$((_r / 1000))"; echo "max=$((_r % 1000))"
      else echo "protect=off"; fi
      _w=$(herald_bat_cget protect); [ -n "$_w" ] && echo "remembered=$_w" ;;
    on)
      _min=${2:-75}; _max=${3:-80}
      herald_bat_int "$_min" && herald_bat_int "$_max" || { echo "err battery_protect 用法: battery protect on [min max],min/max 是百分数"; return; }
      { [ "$_min" -ge 20 ] && [ "$_max" -le 100 ] && [ "$_min" -lt "$_max" ]; } || { echo "err battery_protect 要 20 <= min < max <= 100"; return; }
      _raw=$(herald_bat_protect_raw "$_min" "$_max")
      herald_bat_write "$_node" "$_raw"; _rc=$?
      [ "$_rc" = 1 ] && { echo "err battery_protect 写不进 $_node"; return; }
      herald_bat_cset protect "on:$_min:$_max"
      blog "battery: protect on $_min-$_max raw=$_raw readback=$BAT_RB"
      echo "ok battery protect on min=$_min max=$_max raw=$_raw readback=$BAT_RB" ;;
    off)
      herald_bat_write "$_node" "$BAT_PROT_OFF"; _rc=$?
      [ "$_rc" = 1 ] && { echo "err battery_protect 写不进 $_node"; return; }
      herald_bat_cset protect ""
      blog "battery: protect off readback=$BAT_RB"
      echo "ok battery protect off raw=$BAT_PROT_OFF readback=$BAT_RB" ;;
    *) echo "err battery_protect 用法: battery protect status | on [min max] | off" ;;
  esac
}
# 记住的设置被改回去了就再写一遍
heraldp_bat_reapply_protect() {
  _w=$(herald_bat_cget protect); case "$_w" in on:*) ;; *) return 0 ;; esac
  _min=$(echo "$_w" | cut -d: -f2); _max=$(echo "$_w" | cut -d: -f3)
  herald_bat_int "$_min" && herald_bat_int "$_max" || return 0
  _node=$(herald_bat_node protection); _raw=$(herald_bat_protect_raw "$_min" "$_max")
  [ "$(herald_bat_read "$_node")" = "$_raw" ] && return 0
  herald_bat_write "$_node" "$_raw"; blog "battery: protect 重新套用 $_min-$_max rc=$? readback=$BAT_RB"; return 1
}
BAT_SLOW_MODS="${BAT_SLOW_MODS:-} protect"
