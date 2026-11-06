# battery/health-report 的 broker 插件(装在 /system/etc/herald_payload/plugins/battery-health.sh)。
# 只读:电量、温度、双电芯的循环次数/健康度/日期/厂商,以及几个电池相关节点的当前原始值。读不到的行不输出。
#   回包第一行 ok battery info,后面每行 键=值。
herald_bat_kv() { [ -n "$2" ] && echo "$1=$2"; return 0; }
herald_bat_tenth() {                 # 0.1 的整数(温度) -> 31.7
  case "$1" in -*) _s=-; _n=${1#-} ;; *) _s=; _n=$1 ;; esac
  herald_bat_int "$_n" || return 1
  echo "$_s$((_n / 10)).$((_n % 10))"
}
heraldp_bat_sub_info() {
  echo "ok battery info"
  _b=$BAT_PS/battery
  herald_bat_kv level   "$(herald_bat_read $_b/capacity)"
  herald_bat_kv status  "$(herald_bat_read $_b/status)"
  herald_bat_kv health  "$(herald_bat_read $_b/health)"
  _t=$(herald_bat_read $_b/temp); herald_bat_kv temp_c "$(herald_bat_tenth "$_t")"
  _v=$(herald_bat_read $_b/voltage_now); herald_bat_int "$_v" && herald_bat_kv voltage_mv "$((_v / 1000))"
  _c=$(herald_bat_read $_b/current_now); case "$_c" in -*) _cn=${_c#-}; _cs=- ;; *) _cn=$_c; _cs= ;; esac
  herald_bat_int "$_cn" && herald_bat_kv current_ma "$_cs$((_cn / 1000))"
  herald_bat_kv time_to_full_s  "$(herald_bat_read $_b/time_to_full_now)"
  herald_bat_kv time_to_empty_s "$(herald_bat_read $_b/time_to_empty_now)"
  herald_bat_kv usb_online      "$(herald_bat_read $BAT_PS/usb/online)"
  herald_bat_kv wireless_online "$(herald_bat_read $BAT_PS/wireless/online)"
  # 双电芯:fg1/fg2 是两颗电芯各自的电量计。单位没在真机上核对,这里原样输出(带 _raw)
  _cells=0; _cmax=
  for _n in 1 2; do
    _got=0
    for _k in cycle_count soh temp voltage current activate_date produce_date; do
      _x=$(herald_bat_read "$BAT_FG/fg${_n}_$_k")
      [ -n "$_x" ] && { echo "cell${_n}_${_k}_raw=$_x"; _got=1; }
    done
    _m=$(herald_bat_read "$BAT_FG/battery${_n}_manufacturer"); herald_bat_kv "cell${_n}_manufacturer" "$_m"
    [ -n "$_m" ] && _got=1
    [ "$_got" = 1 ] && _cells=$((_cells + 1))
    _cy=$(herald_bat_read "$BAT_FG/fg${_n}_cycle_count")
    if herald_bat_int "$_cy"; then [ -z "$_cmax" ] || [ "$_cy" -gt "$_cmax" ] && _cmax=$_cy; fi
  done
  echo "cells=$_cells"
  herald_bat_kv cycle_max "$_cmax"
  # 其他电池节点的当前原始值(各功能模块读写的就是这些)
  for _nm in protection limit recharge bypass chg_enable input_susp; do
    herald_bat_kv "node_$_nm" "$(herald_bat_read "$(herald_bat_node $_nm)")"
  done
  return 0
}
