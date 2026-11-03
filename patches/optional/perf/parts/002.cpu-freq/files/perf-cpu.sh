# perf/cpu-freq 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-cpu.sh)。
# CPU 每个簇(cpufreq policy;TB321FU 是 policy0/2/5/7,调速器 walt)的最低/最高频率。写 scaling_min_freq / scaling_max_freq 并读回。
#   perf cpu status
#   perf cpu set <簇号|all> <min|max> <kHz|N%|stock>    N% = 不超过 最高档*N% 的最大一档;stock = 恢复出厂值
#   perf cpu reset                                      全部恢复出厂值(频率、调速器、核心全部在线)并清掉记忆
#   perf cpu governor <簇号|all> <名|stock>             V84:调速器,名字必须在 policyN_governors 里;stock = 出厂调速器
#   perf cpu online <核号|all> <on|off>                 V84:核心开关;至少留一个核在线,cpu0 没有 online 节点时恒在线
# 先后顺序:保证写的时候任意时刻 min <= max(升 max 先升 max,降 max 先降 min)。内核可能把值夹到可用档位,回包里 readback 照实给。
herald_perf_policies() { for _d in "$PERF_CPUDIR"/policy[0-9]*; do [ -d "$_d" ] && echo "${_d##*policy}"; done; }
herald_perf_cpu_avail() { herald_perf_read "$PERF_CPUDIR/policy$1/scaling_available_frequencies"; }
herald_perf_cpu_hw() {                                   # $1 簇号 $2 min|max -> cpuinfo_{min,max}_freq
  herald_perf_read "$PERF_CPUDIR/policy$1/cpuinfo_${2}_freq"
}
herald_perf_cpu_stock() { herald_perf_stock "cpu.$1.$2" "$PERF_CPUDIR/policy$1/scaling_${2}_freq"; }
herald_perf_cpu_write() {                                # $1 簇号 $2 新 min $3 新 max;0=都写成,1=写不进,2=读回不同
  _cd=$PERF_CPUDIR/policy$1; _cmax=$(herald_perf_read "$_cd/scaling_max_freq"); _wrc=0
  if [ -z "$_cmax" ] || [ "$3" -ge "$_cmax" ]; then
    herald_perf_write "$_cd/scaling_max_freq" "$3"; _r1=$?; herald_perf_write "$_cd/scaling_min_freq" "$2"; _r2=$?
  else
    herald_perf_write "$_cd/scaling_min_freq" "$2"; _r2=$?; herald_perf_write "$_cd/scaling_max_freq" "$3"; _r1=$?
  fi
  [ "$_r1" = 1 ] || [ "$_r2" = 1 ] && return 1
  [ "$_r1" = 2 ] || [ "$_r2" = 2 ] && return 2
  return 0
}
# 应用一个簇的一个边界;不动配置里"当前档位"的记忆(profile),只改 cpu.<簇>.<边界>。$1 簇号 $2 min|max $3 规格。结果行在 PERF_MSG,返回 0/1
herald_perf_cpu_apply() {
  _pol=$1; _kind=$2; _spec=$3
  [ -d "$PERF_CPUDIR/policy$_pol" ] || { PERF_MSG="err perf 没有簇 $_pol(有:$(herald_perf_policies | tr '\n' ' ' | sed 's/ $//'))"; return 1; }
  _lo=$(herald_perf_cpu_hw "$_pol" min); _hi=$(herald_perf_cpu_hw "$_pol" max); _av=$(herald_perf_cpu_avail "$_pol")
  herald_perf_int "$_lo" && herald_perf_int "$_hi" || { PERF_MSG="err perf 簇 $_pol 读不到 cpuinfo_min/max_freq"; return 1; }
  _st=$(herald_perf_cpu_stock "$_pol" "$_kind"); herald_perf_int "$_st" || _st=$([ "$_kind" = min ] && echo "$_lo" || echo "$_hi")
  _val=$(herald_perf_resolve "$_spec" "$_av" "$_lo" "$_hi" "$_st") && herald_perf_int "$_val" || { PERF_MSG="err perf 值不对: $_spec(写 kHz 数值、N% 或 stock)"; return 1; }
  _cmin=$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_min_freq"); _cmax=$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_max_freq")
  if [ "$_kind" = min ]; then _nmin=$_val; _nmax=$_cmax; else _nmin=$_cmin; _nmax=$_val; fi
  [ "$_nmin" -le "$_nmax" ] || { PERF_MSG="err perf 簇 $_pol 最小值($_nmin)不能大于最大值($_nmax)"; return 1; }
  herald_perf_cpu_write "$_pol" "$_nmin" "$_nmax"; _rc=$?
  [ "$_rc" = 1 ] && { PERF_MSG="err perf 簇 $_pol 写不进 scaling_${_kind}_freq"; return 1; }
  if [ "$_spec" = stock ]; then herald_perf_cset "cpu.$_pol.$_kind" ""; else herald_perf_cset "cpu.$_pol.$_kind" "$_val"; fi
  _rb=$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_${_kind}_freq")
  blog "perf: cpu policy$_pol $_kind=$_val ($_spec) readback=$_rb"
  PERF_MSG="ok perf cpu policy$_pol $_kind=$_val readback=$_rb"; return 0
}
herald_perf_cpus() { for _d in "$PERF_SYS"/devices/system/cpu/cpu[0-9]*; do [ -d "$_d" ] && echo "${_d##*/cpu}"; done | sort -n; }
herald_perf_cpu_isonline() {                             # $1 核号;没有 online 节点的核(cpu0)视为在线
  _of=$PERF_SYS/devices/system/cpu/cpu$1/online; [ -e "$_of" ] || return 0; [ "$(herald_perf_read "$_of")" = 1 ]
}
herald_perf_gov_stock() { herald_perf_stock "cpu.$1.gov" "$PERF_CPUDIR/policy$1/scaling_governor"; }
herald_perf_gov_apply() {                                # $1 簇号 $2 调速器名|stock;结果行在 PERF_MSG
  _pol=$1; _g=$2
  [ -d "$PERF_CPUDIR/policy$_pol" ] || { PERF_MSG="err perf 没有簇 $_pol(有:$(herald_perf_policies | tr '\n' ' ' | sed 's/ $//'))"; return 1; }
  _stg=$(herald_perf_gov_stock "$_pol")
  [ "$_g" = stock ] && _g=$_stg
  [ -n "$_g" ] || { PERF_MSG="err perf 簇 $_pol 读不到出厂调速器"; return 1; }
  case " $(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_available_governors") " in
    *" $_g "*) ;; *) PERF_MSG="err perf 簇 $_pol 没有调速器 $_g(可选:$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_available_governors"))"; return 1 ;;
  esac
  herald_perf_write "$PERF_CPUDIR/policy$_pol/scaling_governor" "$_g"; _rc=$?
  [ "$_rc" = 1 ] && { PERF_MSG="err perf 簇 $_pol 写不进 scaling_governor"; return 1; }
  if [ "$2" = stock ] || [ "$_g" = "$_stg" ]; then herald_perf_cset "cpu.$_pol.gov" ""; else herald_perf_cset "cpu.$_pol.gov" "$_g"; fi
  blog "perf: cpu policy$_pol governor=$_g readback=$PERF_RB"
  PERF_MSG="ok perf cpu policy$_pol governor=$_g readback=$PERF_RB"; [ "$_rc" = 2 ] && return 1; return 0
}
herald_perf_online_apply() {                             # $1 核号 $2 on|off;结果行在 PERF_MSG
  _c=$1; _f=$PERF_SYS/devices/system/cpu/cpu$_c/online
  [ -d "$PERF_SYS/devices/system/cpu/cpu$_c" ] || { PERF_MSG="err perf 没有核心 $_c(有:$(herald_perf_cpus | tr '\n' ' ' | sed 's/ $//'))"; return 1; }
  [ -e "$_f" ] || { [ "$2" = on ] && { PERF_MSG="ok perf cpu cpu$_c online=1(此核没有开关,恒在线)"; return 0; }; PERF_MSG="err perf cpu$_c 没有 online 节点,关不掉"; return 1; }
  if [ "$2" = off ]; then
    _left=0; for _o in $(herald_perf_cpus); do [ "$_o" = "$_c" ] && continue; herald_perf_cpu_isonline "$_o" && _left=$((_left + 1)); done
    [ "$_left" -ge 1 ] || { PERF_MSG="err perf 至少要留一个核心在线,不能关 cpu$_c"; return 1; }
    herald_perf_write "$_f" 0; _rc=$?
    if [ "$_rc" = 1 ] || [ "$PERF_RB" != 0 ]; then PERF_MSG="err perf 关不掉 cpu$_c(readback=$PERF_RB)"; return 1; fi
    herald_perf_cset "cpu.$_c.off" 1
  else
    herald_perf_write "$_f" 1; _rc=$?
    if [ "$_rc" = 1 ] || [ "$PERF_RB" != 1 ]; then PERF_MSG="err perf 开不了 cpu$_c(readback=$PERF_RB)"; return 1; fi
    herald_perf_cset "cpu.$_c.off" ""
  fi
  blog "perf: cpu$_c online=$PERF_RB"
  PERF_MSG="ok perf cpu cpu$_c online=$PERF_RB"; return 0
}
heraldp_perf_sub_cpu() {
  set -- "${1:-}" "${2:-}" "${3:-}" "${4:-}"   # broker 是 set -u:缺参数时给空串,走用法提示
  case "$1" in
    status|"")
      _ps=$(herald_perf_policies); [ -n "$_ps" ] || { echo "err perf 这台机器没有 cpufreq 节点($PERF_CPUDIR)"; return; }
      echo "ok perf cpu"; echo "policies=$(echo $_ps | tr ' ' ',')"
      for _pol in $_ps; do
        _d=$PERF_CPUDIR/policy$_pol
        echo "policy${_pol}_cpus=$(herald_perf_read "$_d/related_cpus" | tr ' ' ',')"
        echo "policy${_pol}_governor=$(herald_perf_read "$_d/scaling_governor")"
        echo "policy${_pol}_governors=$(herald_perf_read "$_d/scaling_available_governors" | tr ' ' ',')"
        echo "policy${_pol}_stock_governor=$(sed -n "s/^cpu.$_pol.gov=//p" "$PERF_STOCK" 2>/dev/null | tail -1)"
        echo "policy${_pol}_custom_governor=$(herald_perf_cget cpu.$_pol.gov)"
        echo "policy${_pol}_cur=$(herald_perf_read "$_d/scaling_cur_freq")"
        echo "policy${_pol}_min=$(herald_perf_read "$_d/scaling_min_freq")"
        echo "policy${_pol}_max=$(herald_perf_read "$_d/scaling_max_freq")"
        echo "policy${_pol}_hw_min=$(herald_perf_cpu_hw "$_pol" min)"
        echo "policy${_pol}_hw_max=$(herald_perf_cpu_hw "$_pol" max)"
        echo "policy${_pol}_avail=$(herald_perf_cpu_avail "$_pol" | tr ' ' ',')"
        echo "policy${_pol}_stock_min=$(sed -n "s/^cpu.$_pol.min=//p" "$PERF_STOCK" 2>/dev/null | tail -1)"
        echo "policy${_pol}_stock_max=$(sed -n "s/^cpu.$_pol.max=//p" "$PERF_STOCK" 2>/dev/null | tail -1)"
        echo "policy${_pol}_custom=$(herald_perf_cget cpu.$_pol.min):$(herald_perf_cget cpu.$_pol.max)"
      done
      echo "cpus=$(herald_perf_cpus | tr '\n' ',' | sed 's/,$//')"
      for _c in $(herald_perf_cpus); do
        if herald_perf_cpu_isonline "$_c"; then echo "cpu${_c}_online=1"; else echo "cpu${_c}_online=0"; fi
        [ -e "$PERF_SYS/devices/system/cpu/cpu$_c/online" ] && echo "cpu${_c}_switchable=1" || echo "cpu${_c}_switchable=0"
      done ;;
    set)
      { [ -n "$2" ] && { [ "$3" = min ] || [ "$3" = max ]; } && [ -n "$4" ]; } || { echo "err perf 用法: perf cpu set <簇号|all> <min|max> <kHz|N%|stock>"; return; }
      _targets=$2; [ "$2" = all ] && _targets=$(herald_perf_policies)
      echo "ok perf cpu set"; _bad=0
      for _pol in $_targets; do
        if herald_perf_cpu_apply "$_pol" "$3" "$4"; then echo "${PERF_MSG#ok perf cpu }"; else echo "$PERF_MSG"; _bad=1; fi
      done
      [ "$_bad" = 0 ] && herald_perf_cset profile "" ;;
    governor)
      { [ -n "$2" ] && [ -n "$3" ]; } || { echo "err perf 用法: perf cpu governor <簇号|all> <调速器名|stock>"; return; }
      _targets=$2; [ "$2" = all ] && _targets=$(herald_perf_policies)
      echo "ok perf cpu governor"; _bad=0
      for _pol in $_targets; do
        if herald_perf_gov_apply "$_pol" "$3"; then echo "${PERF_MSG#ok perf cpu }"; else echo "$PERF_MSG"; _bad=1; fi
      done ;;
    online)
      { [ -n "$2" ] && { [ "$3" = on ] || [ "$3" = off ]; }; } || { echo "err perf 用法: perf cpu online <核号|all> <on|off>"; return; }
      _targets=$2; [ "$2" = all ] && _targets=$(herald_perf_cpus)
      echo "ok perf cpu online"
      for _c in $_targets; do
        herald_perf_online_apply "$_c" "$3" && echo "${PERF_MSG#ok perf cpu }" || echo "$PERF_MSG"
      done ;;
    reset)
      for _c in $(herald_perf_cpus); do herald_perf_online_apply "$_c" on >/dev/null; done
      for _pol in $(herald_perf_policies); do
        herald_perf_gov_apply "$_pol" stock >/dev/null
        herald_perf_cpu_apply "$_pol" max stock >/dev/null; herald_perf_cpu_apply "$_pol" min stock >/dev/null
      done
      herald_perf_cset profile ""; echo "ok perf cpu reset" ;;
    *) echo "err perf 用法: perf cpu status | set <簇号|all> <min|max> <kHz|N%|stock> | governor <簇号|all> <名|stock> | online <核号|all> <on|off> | reset" ;;
  esac
}
heraldp_perf_reapply_cpu() {                             # 记住的 cpu.<簇>.min|max / 调速器 / 关核 被改回去就重写
  for _pol in $(herald_perf_policies); do
    _gw=$(herald_perf_cget "cpu.$_pol.gov"); [ -n "$_gw" ] || continue
    herald_perf_gov_stock "$_pol" >/dev/null
    [ "$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_governor")" = "$_gw" ] || { herald_perf_gov_apply "$_pol" "$_gw" >/dev/null; blog "perf: cpu policy$_pol 调速器被改回去了,重新套用 $_gw"; }
  done
  for _c in $(herald_perf_cpus); do
    [ "$(herald_perf_cget "cpu.$_c.off")" = 1 ] || continue
    herald_perf_cpu_isonline "$_c" && { herald_perf_online_apply "$_c" off >/dev/null; blog "perf: cpu$_c 被拉起来了,重新关掉"; }
  done
  for _pol in $(herald_perf_policies); do
    for _kind in min max; do
      _w=$(herald_perf_cget "cpu.$_pol.$_kind"); [ -n "$_w" ] || continue
      herald_perf_cpu_stock "$_pol" "$_kind" >/dev/null     # 开机后第一次写之前先把出厂值记下来
      [ "$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_${_kind}_freq")" = "$_w" ] && continue
      _cmin=$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_min_freq"); _cmax=$(herald_perf_read "$PERF_CPUDIR/policy$_pol/scaling_max_freq")
      if [ "$_kind" = min ]; then herald_perf_cpu_write "$_pol" "$_w" "$_cmax"; else herald_perf_cpu_write "$_pol" "$_cmin" "$_w"; fi
      blog "perf: cpu policy$_pol $_kind 被改回去了,重新套用 $_w rc=$?"
    done
  done
}
PERF_SLOW_MODS="${PERF_SLOW_MODS:-} cpu"
