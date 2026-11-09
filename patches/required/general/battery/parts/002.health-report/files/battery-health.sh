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
  # 整机:健康度、循环次数、满电容量 / 设计容量(电池管理 App 显示"满电容量")
  herald_bat_kv soh                    "$(herald_bat_read $_b/soh)"
  herald_bat_kv cycle_count            "$(herald_bat_read $_b/cycle_count)"
  herald_bat_kv charge_full_uah        "$(herald_bat_read $_b/charge_full)"
  herald_bat_static design_uah "$_b/charge_full_design"; herald_bat_kv charge_full_design_uah "$_bsv"
  # 双电芯:fg1/fg2 是两颗电芯各自的电量计。单位没在真机上核对,这里原样输出(带 _raw)
  _cells=0; _cmax=
  for _n in 1 2; do
    _got=0
    _cy=
    for _k in cycle_count soh temp voltage current; do
      _x=$(herald_bat_read "$BAT_FG/fg${_n}_$_k")
      [ -n "$_x" ] && { echo "cell${_n}_${_k}_raw=$_x"; _got=1; }
      [ "$_k" = cycle_count ] && _cy=$_x
    done
    for _k in activate_date produce_date; do           # 不变的值,每次开机只读一次(I2C,一个 150 ms)
      herald_bat_static "fg${_n}_$_k" "$BAT_FG/fg${_n}_$_k"; _x=$_bsv
      [ -n "$_x" ] && { echo "cell${_n}_${_k}_raw=$_x"; _got=1; }
    done
    herald_bat_static "mfr$_n" "$BAT_FG/battery${_n}_manufacturer"; _m=$_bsv; herald_bat_kv "cell${_n}_manufacturer" "$_m"
    [ -n "$_m" ] && _got=1
    [ "$_got" = 1 ] && _cells=$((_cells + 1))
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
