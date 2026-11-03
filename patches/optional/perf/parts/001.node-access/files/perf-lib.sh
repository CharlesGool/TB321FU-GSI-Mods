# perf/node-access 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-lib.sh,由 herald-start.sh source)。
# 性能调节的公共部分:节点读写(写完读回)、配置记忆、"出厂值"记录、`perf` 命令分发、空闲时重新套用。
# 其他 perf/* 模块各自定义 heraldp_perf_sub_<子命令>(),这里的 heraldp_cmd_perf 按子命令名找过去。用到 herald-start.sh 的 blog、$STATE、HERALDP_IDLE。
#
# 范围:只动 CPU 每个簇的 scaling_min/max_freq 和 GPU devfreq 的 min/max_freq(用户态频率上下限,和内核/温控各自的限制取交集,
# 所以温控照常限频,这里不绕过它)。不碰调速器、不碰温控、不碰电压。
PERF_SYS=${HERALD_PERF_SYSROOT:-/sys}                    # 测试时可换成假的 sys 树
PERF_CPUDIR=$PERF_SYS/devices/system/cpu/cpufreq
PERF_GPUDIR=$PERF_SYS/class/kgsl/kgsl-3d0/devfreq
PERF_CONF=$STATE/perf.conf                            # 用户设过的值(重启后重新套用):cpu.<簇>.min|max=kHz、gpu.min|max=Hz、profile=名字、game_profile=名字
PERF_STOCK=$STATE/perf.stock                          # 本次开机的"出厂值"(第一次要改之前读到的),开机 id 变了就作废重记
PERF_BOOTID=${HERALD_PERF_BOOTID:-/proc/sys/kernel/random/boot_id}
herald_perf_read() { [ -r "$1" ] || return 1; _pv=$(cat "$1" 2>/dev/null) || return 1; printf '%s' "$_pv" | tr -d '\r\n'; }
herald_perf_write() {                                    # 写节点并读回:写不进去返回 1;读回和写入不同返回 2(值在 $PERF_RB)
  [ -e "$1" ] || { PERF_RB=; return 1; }
  printf '%s' "$2" > "$1" 2>/dev/null || { PERF_RB=; return 1; }
  PERF_RB=$(herald_perf_read "$1")
  [ "$PERF_RB" = "$2" ] || return 2
  return 0
}
herald_perf_int() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; }

herald_perf_cget() { [ -f "$PERF_CONF" ] && sed -n "s/^$1=//p" "$PERF_CONF" | tail -1; }
herald_perf_cset() {                                     # $1 键 $2 值;值为空 = 删掉这个键
  { [ -f "$PERF_CONF" ] && grep -v "^$1=" "$PERF_CONF"; [ -n "$2" ] && echo "$1=$2"; } > "$PERF_CONF.new" 2>/dev/null
  mv -f "$PERF_CONF.new" "$PERF_CONF" 2>/dev/null
}
# 出厂值:第一次要改某个节点之前读一下它,记在 $PERF_STOCK(带开机 id);之后"恢复默认"就写回这个值
herald_perf_stock() {                                    # $1 键 $2 节点 -> 输出出厂值(读不到输出空)
  _bid=$(herald_perf_read "$PERF_BOOTID")
  if [ -f "$PERF_STOCK" ] && [ "$(sed -n 's/^boot=//p' "$PERF_STOCK")" != "$_bid" ]; then rm -f "$PERF_STOCK"; fi
  [ -f "$PERF_STOCK" ] || echo "boot=$_bid" > "$PERF_STOCK"
  _sv=$(sed -n "s/^$1=//p" "$PERF_STOCK" | tail -1)
  if [ -z "$_sv" ]; then _sv=$(herald_perf_read "$2"); [ -n "$_sv" ] && echo "$1=$_sv" >> "$PERF_STOCK"; fi
  echo "$_sv"
}
# 百分比 -> 频率:在可用频率表($1,空格分隔)里选"不超过 上限*百分比/100 的最大一档",都超过就选最低档
herald_perf_pick() {                                     # $1 可用频率表 $2 上限(取最大档) $3 百分比
  _pmax=$2; for _pf in $1; do [ "$_pf" -gt "$_pmax" ] && _pmax=$_pf; done
  _pt=$((_pmax / 100 * $3)); _pbest=""; _plow=""
  for _pf in $1; do
    { [ -z "$_plow" ] || [ "$_pf" -lt "$_plow" ]; } && _plow=$_pf
    [ "$_pf" -le "$_pt" ] && { [ -z "$_pbest" ] || [ "$_pf" -gt "$_pbest" ]; } && _pbest=$_pf
  done
  echo "${_pbest:-$_plow}"
}
# 规格 -> 具体频率:stock | N% | 具体数值(夹在 [最低,最高] 里)。$1 规格 $2 可用频率表 $3 最低 $4 最高 $5 出厂值
herald_perf_resolve() {
  case "$1" in
    stock) echo "$5" ;;
    *%) _pp=${1%\%}; herald_perf_int "$_pp" && [ "$_pp" -ge 1 ] && [ "$_pp" -le 100 ] || return 1
        if [ -n "$2" ]; then herald_perf_pick "$2" "$4" "$_pp"; else echo $(($4 / 100 * _pp)); fi ;;
    *)  herald_perf_int "$1" || return 1
        _pv2=$1; [ "$_pv2" -lt "$3" ] && _pv2=$3; [ "$_pv2" -gt "$4" ] && _pv2=$4; echo "$_pv2" ;;
  esac
}

heraldp_cmd_perf() {
  set -- $1
  _sub=${1:-}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err perf 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_perf_sub_$_sub" >/dev/null 2>&1; then "heraldp_perf_sub_$_sub" "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
  else echo "err perf 没有子命令 $_sub(装了哪些性能模块看 heraldctl help)"; fi
}
# 空闲(主循环每 5 秒调一次):每约 30 秒让各模块核对"记住的设置"还在不在(温控/性能 HAL/热插拔可能改回去)。
#   模块定义 heraldp_perf_reapply_<名字>(),并把名字追加进 PERF_SLOW_MODS(变量不在这里赋初值:插件按字母序加载,模块可能先于本文件)。
PERF_IDLE_N=0
heraldp_perf_idle() {
  if [ "$PERF_IDLE_N" -eq 0 ] || [ "$PERF_IDLE_N" -ge 6 ]; then
    PERF_IDLE_N=0
    for _m in $PERF_SLOW_MODS; do type "heraldp_perf_reapply_$_m" >/dev/null 2>&1 && "heraldp_perf_reapply_$_m"; done
  fi
  PERF_IDLE_N=$((PERF_IDLE_N + 1))
}
HERALDP_IDLE="${HERALDP_IDLE:-} heraldp_perf_idle"
