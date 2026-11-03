# refresh-rate/control 的 broker 插件(装在 /system/etc/herald_payload/plugins/refresh-rate.sh)。
# 刷新率调节:锁定到某一档,或限定范围让系统在范围内自动挑。写系统的 min_refresh_rate / peak_refresh_rate
# (Settings.System,DisplayModeDirector 的"用户设置"投票读的就是这两个键;设置里"流畅显示"开关写的也是 peak_refresh_rate)。
# 用到 herald-start.sh 的 herald_sys、blog、$W、$STATE、herald_int_in。
#   refresh status | modes | set <Hz> | range <最小> <最大> | auto
#   面板的档位从 `dumpsys display` 的 supportedModes 读(TB321FU:30/60/90/120/144/165;系统报 120.00001、60.000004 这种,四舍五入成整数)。
#   set N = min、peak 都写 N(锁定);range A B = min A、peak B(A=0 不设下限,B=0 不设上限);auto = 两个键都删掉,恢复系统默认。
#   别的模块(refresh-rate/adaptive)往 heraldp_ref_sub_<名字> 加子命令,dispatcher 在这里。
REF_CONF=$STATE/refresh.conf     # 记忆:mode=manual|adaptive、default=…、app.<包名>=…、battery=…(adaptive-refresh 用)
herald_ref_sget() { herald_sys /system/bin/settings get system "$1" | tr -d '\r\n'; }
herald_ref_sput() { herald_sys /system/bin/settings put system "$1" "$2" >/dev/null 2>&1; [ "$(herald_ref_sget "$1")" = "$2" ]; }
herald_ref_sdel() {                 # 删完读回核对,没删掉(V75 真机偶发:auto 返回 ok 但 min/peak 还是 60)就重试,最多 4 次
  _n=0
  while [ "$_n" -lt 4 ]; do
    herald_sys /system/bin/settings delete system "$1" >/dev/null 2>&1
    case "$(herald_ref_sget "$1")" in ""|null) return 0 ;; esac
    _n=$((_n + 1)); sleep 1
  done
  return 1
}
herald_ref_round() {                # 59.99999 -> 60,120.00001 -> 120
  _i=${1%%.*}; _f=${1#*.}; [ "$_f" = "$1" ] && _f=0
  case "$_i" in ""|*[!0-9]*) return 1 ;; esac
  case "$_f" in [5-9]*) _i=$((_i + 1)) ;; esac
  echo "$_i"
}
herald_ref_modes() {                # 面板支持的刷新率,逗号分隔,升序、去重
  herald_sys /system/bin/dumpsys display > "$W/herald_ref_d" 2>/dev/null
  _list=""
  for _f in $(grep -o 'height=[0-9]*, fps=[0-9.]*' "$W/herald_ref_d" | sed 's/.*fps=//'); do
    _r=$(herald_ref_round "$_f") && _list="$_list $_r"
  done
  rm -f "$W/herald_ref_d"
  echo $_list | tr ' ' '\n' | sort -n -u | tr '\n' ',' | sed 's/,$//'
}
herald_ref_active() {               # 现在实际在跑的刷新率
  herald_sys /system/bin/dumpsys display > "$W/herald_ref_d" 2>/dev/null
  _a=$(grep -m1 'mActiveSfDisplayMode=' "$W/herald_ref_d" | grep -o 'peakRefreshRate=[0-9.]*' | cut -d= -f2)
  [ -n "$_a" ] || _a=$(grep -m1 -o 'renderFrameRate [0-9.]*' "$W/herald_ref_d" | head -1 | cut -d' ' -f2)
  rm -f "$W/herald_ref_d"
  [ -n "$_a" ] && herald_ref_round "$_a"
}
herald_ref_has() {                  # $1 在 $2(逗号列表)里
  case ",$2," in *",$1,"*) return 0 ;; esac; return 1
}
# 把"规格"套到系统设置上。规格:auto | N | A-B。出错时输出原因并返回 1
herald_ref_apply() {
  case "$1" in
    auto) _r=0; herald_ref_sdel min_refresh_rate || _r=1; herald_ref_sdel peak_refresh_rate || _r=1
          [ "$_r" = 0 ] || echo "删不掉 min/peak_refresh_rate(重试 4 次仍在)"; return $_r ;;
    *-*)  _lo=${1%%-*}; _hi=${1#*-} ;;
    *)    _lo=$1; _hi=$1 ;;
  esac
  herald_int_in "$_lo" 0 999 && herald_int_in "$_hi" 0 999 || { echo "刷新率要是整数"; return 1; }
  _modes=$(herald_ref_modes)
  [ "$_lo" = 0 ] || herald_ref_has "$_lo" "$_modes" || { echo "$_lo 不是面板支持的档位($_modes)"; return 1; }
  [ "$_hi" = 0 ] || herald_ref_has "$_hi" "$_modes" || { echo "$_hi 不是面板支持的档位($_modes)"; return 1; }
  [ "$_hi" = 0 ] || [ "$_lo" -le "$_hi" ] || { echo "最小值不能大于最大值"; return 1; }
  if [ "$_lo" = 0 ]; then herald_ref_sdel min_refresh_rate; else herald_ref_sput min_refresh_rate "$_lo" || { echo "写不进 min_refresh_rate"; return 1; }; fi
  if [ "$_hi" = 0 ]; then herald_ref_sput peak_refresh_rate Infinity || { echo "写不进 peak_refresh_rate"; return 1; }
  else herald_ref_sput peak_refresh_rate "$_hi" || { echo "写不进 peak_refresh_rate"; return 1; }; fi
  return 0
}
# 记忆(键=值,一行一个)
herald_ref_cget() { _rv=""; [ -f "$REF_CONF" ] && while IFS= read -r _l; do case "$_l" in "$1="*) _rv=${_l#*=} ;; esac; done < "$REF_CONF"; echo "$_rv"; }
herald_ref_cset() {                 # $1 键 $2 值;值为空 = 删掉这个键
  { [ -f "$REF_CONF" ] && while IFS= read -r _l; do case "$_l" in "$1="*) ;; *) echo "$_l" ;; esac; done < "$REF_CONF"
    [ -n "$2" ] && echo "$1=$2"; } > "$REF_CONF.new" 2>/dev/null
  mv -f "$REF_CONF.new" "$REF_CONF" 2>/dev/null
}

heraldp_cmd_refresh() {
  set -- $1
  _sub=$1; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err refresh 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_ref_sub_$_sub" >/dev/null 2>&1; then "heraldp_ref_sub_$_sub" "$@"
  else echo "err refresh 没有子命令 $_sub(装了哪些见 heraldctl help)"; fi
}
heraldp_ref_sub_modes() { echo "ok refresh modes"; echo "modes=$(herald_ref_modes)"; }
heraldp_ref_sub_status() {
  echo "ok refresh status"
  echo "active=$(herald_ref_active)"
  echo "min=$(herald_ref_sget min_refresh_rate | sed 's/^null$//')"
  echo "peak=$(herald_ref_sget peak_refresh_rate | sed 's/^null$//')"
  echo "modes=$(herald_ref_modes)"
  echo "mode=$(herald_ref_cget mode | sed 's/^$/manual/')"
}
heraldp_ref_sub_set() {
  herald_int_in "$1" 1 999 || { echo "err refresh 用法: refresh set <Hz>"; return; }
  _e=$(herald_ref_apply "$1") || { echo "err refresh $_e"; return; }
  herald_ref_cset mode ""; blog "refresh: 锁定 $1Hz"
  echo "ok refresh set $1"
}
heraldp_ref_sub_range() {
  { herald_int_in "$1" 0 999 && herald_int_in "$2" 0 999; } || { echo "err refresh 用法: refresh range <最小Hz> <最大Hz>(0 = 不限)"; return; }
  _e=$(herald_ref_apply "$1-$2") || { echo "err refresh $_e"; return; }
  herald_ref_cset mode ""; blog "refresh: 范围 $1-$2"
  echo "ok refresh range $1-$2"
}
heraldp_ref_sub_auto() {
  _e=$(herald_ref_apply auto) || { echo "err refresh $_e"; return; }
  herald_ref_cset mode ""; blog "refresh: 恢复系统默认"
  echo "ok refresh auto"
}
