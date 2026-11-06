# battery/charge-limit 的 broker 插件(装在 /system/etc/herald_payload/plugins/battery-limit.sh)。
# 充电上限:电量到上限就不再充,掉到"上限 x 回充比例"以下才重新充。写原厂的 battery/protection_setting_eu,
# 并把回充比例写进 battery/recharge_setting。
#   原厂做法(ZuiBatteryManagerService.setMaxBatteryChargingLevel):写 100000 + 回充比例*上限*10 + 上限,回充比例 95。
#   这里改成不依赖整除的写法:100000 + 下限*1000 + 上限,下限 = 上限*回充比例/100;上限是 20 的倍数时和原厂一模一样
#   (80% -> 176080,100% -> 195100)。
#   battery limit status | <20..100> [回充比例] | off     off = 上限 100
BAT_LIM_RECHARGE=95
herald_bat_limit_raw() { echo $((100000 + ($1 * $2 / 100) * 1000 + $1)); }
heraldp_bat_sub_limit() {
  _node=$(herald_bat_node limit); _rnode=$(herald_bat_node recharge)
  case "$1" in
    status|"")
      _raw=$(herald_bat_read "$_node") || { echo "err battery_limit 读不了 $_node(这台机器没有这个节点?)"; return; }
      echo "ok battery limit"
      echo "raw=$_raw"
      if herald_bat_int "$_raw" && [ "$_raw" -ge 100000 ]; then
        _r=$((_raw - 100000)); echo "floor=$((_r / 1000))"; echo "limit=$((_r % 1000))"
      fi
      _rc=$(herald_bat_read "$_rnode"); [ -n "$_rc" ] && echo "recharge_raw=$_rc"
      _w=$(herald_bat_cget limit); [ -n "$_w" ] && echo "remembered=$_w" ;;
    off|100) heraldp_bat_limit_set 100 "$BAT_LIM_RECHARGE" off ;;
    *)
      herald_bat_int "$1" || { echo "err battery_limit 用法: battery limit status | <20..100> [回充比例] | off"; return; }
      heraldp_bat_limit_set "$1" "${2:-$BAT_LIM_RECHARGE}" on ;;
  esac
}
heraldp_bat_limit_set() {   # $1 上限 $2 回充比例 $3 on|off
  herald_bat_int "$2" || { echo "err battery_limit 回充比例是百分数"; return; }
  { [ "$1" -ge 20 ] && [ "$1" -le 100 ] && [ "$2" -ge 50 ] && [ "$2" -le 100 ]; } || { echo "err battery_limit 要 20 <= 上限 <= 100,50 <= 回充比例 <= 100"; return; }
  _node=$(herald_bat_node limit); _rnode=$(herald_bat_node recharge); _raw=$(herald_bat_limit_raw "$1" "$2")
  herald_bat_write "$_node" "$_raw"; _rc=$?
  [ "$_rc" = 1 ] && { echo "err battery_limit 写不进 $_node"; return; }
  _rb=$BAT_RB
  herald_bat_write "$_rnode" "$2"; _rr=$?     # 回充比例节点写不进不算失败(记在回包里)
  if [ "$3" = on ]; then herald_bat_cset limit "$1:$2"; else herald_bat_cset limit ""; fi
  blog "battery: limit $3 $1 recharge=$2 raw=$_raw readback=$_rb recharge_rc=$_rr"
  echo "ok battery limit $3 limit=$1 recharge=$2 raw=$_raw readback=$_rb recharge_write=$_rr"
}
heraldp_bat_reapply_limit() {
  _w=$(herald_bat_cget limit); [ -n "$_w" ] || return 0
  _p=${_w%%:*}; _q=${_w#*:}
  herald_bat_int "$_p" && herald_bat_int "$_q" || return 0
  _node=$(herald_bat_node limit); _raw=$(herald_bat_limit_raw "$_p" "$_q")
  [ "$(herald_bat_read "$_node")" = "$_raw" ] && return 0
  herald_bat_write "$_node" "$_raw"; blog "battery: limit 重新套用 $_p/$_q rc=$? readback=$BAT_RB"
  herald_bat_write "$(herald_bat_node recharge)" "$_q"; return 1
}
BAT_SLOW_MODS="${BAT_SLOW_MODS:-} limit"
