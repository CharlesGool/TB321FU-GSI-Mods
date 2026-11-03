# perf/gpu-freq 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-gpu.sh)。
# GPU(Adreno,kgsl 的 devfreq)的最低/最高频率:写 devfreq/min_freq、devfreq/max_freq(单位 Hz),并读回。
#   perf gpu status
#   perf gpu set <min|max> <Hz|NMHz|N%|stock>     N% = 不超过 最高档*N% 的最大一档;stock = 恢复出厂值
#   perf gpu reset
# GPU 节点 shell 读不到(权限),只有 root 的 broker 能读写;没有这个节点的机器返回 err。
herald_perf_gpu_avail() { herald_perf_read "$PERF_GPUDIR/available_frequencies"; }
herald_perf_gpu_has() { [ -e "$PERF_GPUDIR/max_freq" ]; }
herald_perf_gpu_bounds() {                               # 输出 "最低 最高"
  _glo=""; _ghi=""
  for _gf in $(herald_perf_gpu_avail); do
    { [ -z "$_glo" ] || [ "$_gf" -lt "$_glo" ]; } && _glo=$_gf
    { [ -z "$_ghi" ] || [ "$_gf" -gt "$_ghi" ]; } && _ghi=$_gf
  done
  echo "$_glo $_ghi"
}
herald_perf_gpu_write() {                                # $1 新 min $2 新 max
  _gmax=$(herald_perf_read "$PERF_GPUDIR/max_freq")
  if [ -z "$_gmax" ] || [ "$2" -ge "$_gmax" ]; then
    herald_perf_write "$PERF_GPUDIR/max_freq" "$2"; _r1=$?; herald_perf_write "$PERF_GPUDIR/min_freq" "$1"; _r2=$?
  else
    herald_perf_write "$PERF_GPUDIR/min_freq" "$1"; _r2=$?; herald_perf_write "$PERF_GPUDIR/max_freq" "$2"; _r1=$?
  fi
  [ "$_r1" = 1 ] || [ "$_r2" = 1 ] && return 1
  [ "$_r1" = 2 ] || [ "$_r2" = 2 ] && return 2
  return 0
}
herald_perf_gpu_apply() {                                # $1 min|max $2 规格。结果行在 PERF_MSG,返回 0/1
  _kind=$1; _spec=$2
  herald_perf_gpu_has || { PERF_MSG="err perf 这台机器没有 GPU 频率节点($PERF_GPUDIR)"; return 1; }
  set -- $(herald_perf_gpu_bounds); _lo=$1; _hi=$2; _av=$(herald_perf_gpu_avail)
  herald_perf_int "$_lo" && herald_perf_int "$_hi" || { PERF_MSG="err perf 读不到 GPU 可用频率表"; return 1; }
  case "$_spec" in *MHz) _n=${_spec%MHz}; herald_perf_int "$_n" && _spec=$((_n * 1000000)) ;; esac
  _st=$(herald_perf_stock "gpu.$_kind" "$PERF_GPUDIR/${_kind}_freq"); herald_perf_int "$_st" || _st=$([ "$_kind" = min ] && echo "$_lo" || echo "$_hi")
  _val=$(herald_perf_resolve "$_spec" "$_av" "$_lo" "$_hi" "$_st") && herald_perf_int "$_val" || { PERF_MSG="err perf 值不对: $_spec(写 Hz、NMHz、N% 或 stock)"; return 1; }
  _cmin=$(herald_perf_read "$PERF_GPUDIR/min_freq"); _cmax=$(herald_perf_read "$PERF_GPUDIR/max_freq")
  if [ "$_kind" = min ]; then _nmin=$_val; _nmax=$_cmax; else _nmin=$_cmin; _nmax=$_val; fi
  [ "$_nmin" -le "$_nmax" ] || { PERF_MSG="err perf GPU 最小值($_nmin)不能大于最大值($_nmax)"; return 1; }
  herald_perf_gpu_write "$_nmin" "$_nmax"; _rc=$?
  [ "$_rc" = 1 ] && { PERF_MSG="err perf GPU 写不进 ${_kind}_freq"; return 1; }
  if [ "$_spec" = stock ]; then herald_perf_cset "gpu.$_kind" ""; else herald_perf_cset "gpu.$_kind" "$_val"; fi
  _rb=$(herald_perf_read "$PERF_GPUDIR/${_kind}_freq")
  blog "perf: gpu $_kind=$_val ($_spec) readback=$_rb"
  PERF_MSG="ok perf gpu $_kind=$_val readback=$_rb"; return 0
}
heraldp_perf_sub_gpu() {
  case "$1" in
    status|"")
      herald_perf_gpu_has || { echo "err perf 这台机器没有 GPU 频率节点($PERF_GPUDIR)"; return; }
      echo "ok perf gpu"
      echo "cur=$(herald_perf_read "$PERF_GPUDIR/cur_freq")"
      echo "min=$(herald_perf_read "$PERF_GPUDIR/min_freq")"
      echo "max=$(herald_perf_read "$PERF_GPUDIR/max_freq")"
      echo "governor=$(herald_perf_read "$PERF_GPUDIR/governor")"
      echo "avail=$(herald_perf_gpu_avail | tr ' ' ',')"
      echo "stock_min=$(sed -n 's/^gpu.min=//p' "$PERF_STOCK" 2>/dev/null | tail -1)"
      echo "stock_max=$(sed -n 's/^gpu.max=//p' "$PERF_STOCK" 2>/dev/null | tail -1)"
      echo "custom=$(herald_perf_cget gpu.min):$(herald_perf_cget gpu.max)" ;;
    set)
      { { [ "$2" = min ] || [ "$2" = max ]; } && [ -n "$3" ]; } || { echo "err perf 用法: perf gpu set <min|max> <Hz|NMHz|N%|stock>"; return; }
      if herald_perf_gpu_apply "$2" "$3"; then herald_perf_cset profile ""; echo "ok perf gpu set"; echo "${PERF_MSG#ok perf gpu }"; else echo "$PERF_MSG"; fi ;;
    reset)
      herald_perf_gpu_has || { echo "err perf 这台机器没有 GPU 频率节点($PERF_GPUDIR)"; return; }
      herald_perf_gpu_apply max stock >/dev/null; herald_perf_gpu_apply min stock >/dev/null
      herald_perf_cset profile ""; echo "ok perf gpu reset" ;;
    *) echo "err perf 用法: perf gpu status | set <min|max> <Hz|NMHz|N%|stock> | reset" ;;
  esac
}
heraldp_perf_reapply_gpu() {
  herald_perf_gpu_has || return 0
  for _kind in min max; do
    _w=$(herald_perf_cget "gpu.$_kind"); [ -n "$_w" ] || continue
    herald_perf_stock "gpu.$_kind" "$PERF_GPUDIR/${_kind}_freq" >/dev/null
    [ "$(herald_perf_read "$PERF_GPUDIR/${_kind}_freq")" = "$_w" ] && continue
    _cmin=$(herald_perf_read "$PERF_GPUDIR/min_freq"); _cmax=$(herald_perf_read "$PERF_GPUDIR/max_freq")
    if [ "$_kind" = min ]; then herald_perf_gpu_write "$_w" "$_cmax"; else herald_perf_gpu_write "$_cmin" "$_w"; fi
    blog "perf: gpu $_kind 被改回去了,重新套用 $_w rc=$?"
  done
}
PERF_SLOW_MODS="${PERF_SLOW_MODS:-} gpu"
