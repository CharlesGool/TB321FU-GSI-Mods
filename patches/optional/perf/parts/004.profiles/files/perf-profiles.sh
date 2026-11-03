# perf/profiles 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-profiles.sh)。
# 三个档位,一条命令切换(CPU 各簇 + GPU 一起):
#   powersave   省电    CPU 各簇最高频限到 60%、GPU 最高频限到 60%(最低频恢复出厂)
#   balanced    均衡    全部恢复出厂值(默认)
#   performance 性能    CPU 各簇最低频抬到 40%(最高频恢复出厂);GPU 恢复出厂(GPU 自己会按负载升频)
#   perf profile [status] | powersave | balanced | performance
# 内部函数 herald_perf_profile_apply 给别的模块(perf/game-boost)用;herald_perf_snapshot / herald_perf_restore_snapshot 用来"临时切档、之后原样恢复"。
# 手动 perf cpu set / perf gpu set 之后,当前档位显示为 custom。依赖 perf/cpu-freq(GPU 可选:没有 perf/gpu-freq 或没有节点就只调 CPU)。
herald_perf_profile_apply() {                            # $1 档位名;返回 0 成功 1 失败
  case "$1" in
    powersave)   _cmx=60;    _cmn=stock; _gmx=60;    _gmn=stock ;;
    balanced)    _cmx=stock; _cmn=stock; _gmx=stock; _gmn=stock ;;
    performance) _cmx=stock; _cmn=40%;   _gmx=stock; _gmn=stock ;;
    *) return 1 ;;
  esac
  [ "$_cmx" = stock ] || _cmx="$_cmx%"
  [ "$_gmx" = stock ] || _gmx="$_gmx%"
  _pf=0
  for _pol in $(herald_perf_policies); do
    # 先放宽再收紧:先写不会冲突的那个边界
    if [ "$_cmn" = stock ]; then herald_perf_cpu_apply "$_pol" min "$_cmn" >/dev/null || _pf=1; herald_perf_cpu_apply "$_pol" max "$_cmx" >/dev/null || _pf=1
    else herald_perf_cpu_apply "$_pol" max "$_cmx" >/dev/null || _pf=1; herald_perf_cpu_apply "$_pol" min "$_cmn" >/dev/null || _pf=1; fi
  done
  if type herald_perf_gpu_has >/dev/null 2>&1 && herald_perf_gpu_has; then
    herald_perf_gpu_apply min "$_gmn" >/dev/null || _pf=1; herald_perf_gpu_apply max "$_gmx" >/dev/null || _pf=1
  fi
  [ "$1" = balanced ] && herald_perf_cset profile "" || herald_perf_cset profile "$1"
  blog "perf: 档位 $1 rc=$_pf"
  return $_pf
}
herald_perf_profile_name() {
  _pn=$(herald_perf_cget profile)
  if [ -n "$_pn" ]; then echo "$_pn"
  elif grep -qE '^(cpu|gpu)\.' "$PERF_CONF" 2>/dev/null; then echo custom
  else echo balanced; fi
}
herald_perf_snapshot() { grep -E '^(cpu\.|gpu\.|profile=)' "$PERF_CONF" 2>/dev/null; echo "snapshot=1"; }
herald_perf_restore_snapshot() {                         # $1 快照文件:先回到出厂,再把快照里的设置原样写回
  [ -f "$1" ] || return 1
  herald_perf_profile_apply balanced >/dev/null
  _snap_profile=""
  while IFS= read -r _l; do
    case "$_l" in
      cpu.*.min=*|cpu.*.max=*) _k=${_l%%=*}; _pol=${_k#cpu.}; _pol=${_pol%%.*}; _kd=${_k##*.}; herald_perf_cpu_apply "$_pol" "$_kd" "${_l#*=}" >/dev/null ;;
      gpu.min=*|gpu.max=*) _kd=${_l%%=*}; herald_perf_gpu_apply "${_kd#gpu.}" "${_l#*=}" >/dev/null ;;
      profile=*) _snap_profile=${_l#profile=} ;;
    esac
  done < "$1"
  herald_perf_cset profile "${_snap_profile:-}"
  return 0
}
heraldp_perf_sub_profile() {
  case "$1" in
    status|"") echo "ok perf profile"; echo "profile=$(herald_perf_profile_name)" ;;
    powersave|balanced|performance)
      herald_perf_profile_apply "$1" && echo "ok perf profile $1" || echo "err perf 档位 $1 没有全部套用成功(见日志 / perf cpu status)" ;;
    *) echo "err perf 用法: perf profile [status] | powersave | balanced | performance" ;;
  esac
}
