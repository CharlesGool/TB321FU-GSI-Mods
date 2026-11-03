# perf/thermal-readout 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-temps.sh)。只读。
#   perf temps          各类温度的最大值:cpu / gpu / skin(外壳)/ battery,以及全机最高和所在 thermal_zone
#   perf temps all      另外逐个列出所有 thermal_zone(zone.<type>=温度)
# 数据源 /sys/class/thermal/thermal_zone*/{type,temp}(温度毫摄氏度,<= 0 或明显无效的忽略)。
herald_perf_tenths() {                                   # 毫摄氏度 -> 十分之一度(整数);无效输出空
  case "$1" in ""|-*|*[!0-9]*) return 1 ;; esac
  [ "$1" -gt 0 ] && [ "$1" -lt 300000 ] || return 1
  echo $(($1 / 100))
}
herald_perf_fmt() { echo "$(($1 / 10)).$(($1 % 10))"; }
heraldp_perf_sub_temps() { herald_perf_temps_body "${1:-}" 2>/dev/null; }   # 个别 thermal_zone 读出来是非数值/读失败,别把 shell 的报错混进回包(V83 真机多一行错误)
herald_perf_temps_body() {
  _n=0; _cpu=""; _gpu=""; _skin=""; _bat=""; _hot=""; _hotz=""; _all=""
  for _z in "$PERF_SYS"/class/thermal/thermal_zone[0-9]*; do
    [ -d "$_z" ] || continue
    _ty=$(herald_perf_read "$_z/type" | tr 'A-Z' 'a-z'); _t=$(herald_perf_tenths "$(herald_perf_read "$_z/temp")") || continue
    _n=$((_n + 1)); _all="$_all$_ty=$(herald_perf_fmt "$_t")
"
    if [ -z "$_hot" ] || [ "$_t" -gt "$_hot" ]; then _hot=$_t; _hotz=$_ty; fi
    case "$_ty" in
      cpu*) { [ -z "$_cpu" ] || [ "$_t" -gt "$_cpu" ]; } && _cpu=$_t ;;
      gpu*) { [ -z "$_gpu" ] || [ "$_t" -gt "$_gpu" ]; } && _gpu=$_t ;;
      skin*) { [ -z "$_skin" ] || [ "$_t" -gt "$_skin" ]; } && _skin=$_t ;;
      battery*|batt*) { [ -z "$_bat" ] || [ "$_t" -gt "$_bat" ]; } && _bat=$_t ;;
    esac
  done
  [ "$_n" -gt 0 ] || { echo "err perf 读不到 thermal_zone($PERF_SYS/class/thermal)"; return; }
  echo "ok perf temps"
  [ -n "$_cpu" ] && echo "cpu_max_c=$(herald_perf_fmt "$_cpu")"
  [ -n "$_gpu" ] && echo "gpu_max_c=$(herald_perf_fmt "$_gpu")"
  [ -n "$_skin" ] && echo "skin_c=$(herald_perf_fmt "$_skin")"
  [ -n "$_bat" ] && echo "battery_c=$(herald_perf_fmt "$_bat")"
  echo "hottest_c=$(herald_perf_fmt "$_hot")"; echo "hottest_zone=$_hotz"; echo "zones=$_n"
  if [ "$1" = all ]; then printf '%s' "$_all" | sed 's/^/zone./'; fi
}
