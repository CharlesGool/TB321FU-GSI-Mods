# optional/refresh-auto-switch 的 broker 插件(装在 /system/etc/herald_payload/plugins/adaptive-refresh.sh)。
# 按场景自动换刷新率:前台应用有规则就按规则;电量低又没在充电就封顶;都没有就用默认。
# 在 refresh-rate.sh 的 refresh 命令下加子命令,用它的 herald_ref_* 函数;插件按字母序加载,这里只定义函数,
# 运行时才调用 refresh-rate.sh 里的东西,所以加载顺序无所谓。
#   refresh adaptive on|off|status
#   refresh default <规格>             没有别的规则时用的(auto = 系统默认)
#   refresh app <包名> <规格|off>      给某个应用单独定;off = 删掉这条规则
#   refresh apps                       列出所有应用规则
#   refresh battery <电量%> <规格>|off 电量低于 N% 且没在充电时,最高不超过这个规格(只对"锁定/范围"的上限封顶)
# 规格:auto | N | A-B(同 refresh set / range)。规则存在 $REF_CONF(app.<包名>=规格、default=、battery=<电量>:<规格>)。
# 前台应用 = dumpsys window 的 mCurrentFocus(取不到就看 mFocusedApp);每 5 秒(HERALDP_IDLE)判断一次,规格变了才写设置。
REF_SYSROOT=${HERALD_REF_SYSROOT:-/sys}
REF_LAST=""                      # 上次自动套用的规格,避免每 5 秒重写
herald_ref_spec_ok() {              # 规格合法吗(含是不是面板支持的档位)
  case "$1" in auto) return 0 ;; "") return 1 ;; esac
  _lo=${1%%-*}; _hi=${1#*-}
  herald_int_in "$_lo" 0 999 && herald_int_in "$_hi" 0 999 || return 1
  _m=$(herald_ref_modes)
  [ "$_lo" = 0 ] || herald_ref_has "$_lo" "$_m" || return 1
  [ "$_hi" = 0 ] || herald_ref_has "$_hi" "$_m" || return 1
  [ "$_hi" = 0 ] || [ "$_lo" -le "$_hi" ]
}
herald_ref_pkg_ok() { case "$1" in ""|*[!A-Za-z0-9._]*|.*|*..*) return 1 ;; esac; return 0; }
herald_ref_foreground() {           # 前台应用的包名,取不到输出空
  herald_sys /system/bin/dumpsys window > "$W/herald_ref_w" 2>/dev/null
  _l=$(grep -m1 'mCurrentFocus=Window' "$W/herald_ref_w")
  case "$_l" in *null*|"") _l=$(grep -m1 'mFocusedApp=' "$W/herald_ref_w") ;; esac
  rm -f "$W/herald_ref_w"
  # …{abc u0 com.pkg/com.pkg.Activity} 或 …ActivityRecord{abc u0 com.pkg/.Act t12}
  for _t in $_l; do case "$_t" in */*) _p=${_t%%/*}; _p=${_p##*[ \{]}; echo "$_p"; return ;; esac; done
}
herald_ref_battery_cap() {          # 现在该封顶的规格(没触发输出空)
  _bc=$(herald_ref_cget battery); [ -n "$_bc" ] || return 0
  _pct=${_bc%%:*}; _spec=${_bc#*:}
  _lv=$(tr -d '\r\n' < "$REF_SYSROOT/class/power_supply/battery/capacity" 2>/dev/null)
  _st=$(tr -d '\r\n' < "$REF_SYSROOT/class/power_supply/battery/status" 2>/dev/null)
  herald_int_in "$_lv" 0 100 || return 0
  [ "$_st" = Charging ] && return 0
  [ "$_lv" -lt "$_pct" ] && echo "$_spec"
}
herald_ref_cap_apply() {            # $1 规格 $2 封顶规格 -> 输出封顶后的规格(只压最大值)
  case "$2" in auto|"") echo "$1"; return ;; esac
  _chi=${2#*-}
  case "$1" in
    auto) echo "0-$_chi" ;;
    *-*) _lo=${1%%-*}; _hi=${1#*-}
         if [ "$_hi" = 0 ] || [ "$_hi" -gt "$_chi" ]; then _hi=$_chi; fi
         if [ "$_lo" -gt "$_hi" ]; then _lo=$_hi; fi
         echo "$_lo-$_hi" ;;
    *) if [ "$1" -gt "$_chi" ]; then echo "$_chi"; else echo "$1"; fi ;;
  esac
}
herald_ref_desired() {              # 当前该套的规格
  _fg=$(herald_ref_foreground); _d=""
  [ -n "$_fg" ] && _d=$(herald_ref_cget "app.$_fg")
  [ -n "$_d" ] || _d=$(herald_ref_cget default)
  [ -n "$_d" ] || _d=auto
  herald_ref_cap_apply "$_d" "$(herald_ref_battery_cap)"
}
heraldp_ref_idle() {
  [ "$(herald_ref_cget mode)" = adaptive ] || return 0
  _w=$(herald_ref_desired)
  [ "$_w" = "$REF_LAST" ] && return 0
  REF_LAST=$_w
  _e=$(herald_ref_apply "$_w") && blog "refresh: 自动 -> $_w" || blog "refresh: 自动套用 $_w 失败: $_e"
}
HERALDP_IDLE="${HERALDP_IDLE:-} heraldp_ref_idle"

heraldp_ref_sub_adaptive() {
  case "$1" in
    on)  herald_ref_cset mode adaptive; REF_LAST=""; blog "refresh: 自动模式开"; heraldp_ref_idle; echo "ok refresh adaptive on" ;;
    off) herald_ref_cset mode ""; REF_LAST=""; herald_ref_apply auto; blog "refresh: 自动模式关,恢复系统默认"; echo "ok refresh adaptive off" ;;
    status|"")
      echo "ok refresh adaptive"
      [ "$(herald_ref_cget mode)" = adaptive ] && echo "adaptive=on" || echo "adaptive=off"
      echo "default=$(herald_ref_cget default | sed 's/^$/auto/')"
      echo "battery=$(herald_ref_cget battery)"
      echo "foreground=$(herald_ref_foreground)"
      echo "applied=$REF_LAST"
      echo "apps=$(grep -c '^app\.' "$REF_CONF" 2>/dev/null || echo 0)" ;;
    *) echo "err refresh 用法: refresh adaptive on|off|status" ;;
  esac
}
heraldp_ref_sub_default() {
  herald_ref_spec_ok "$1" || { echo "err refresh 用法: refresh default <auto|Hz|最小-最大>(档位见 refresh modes)"; return; }
  if [ "$1" = auto ]; then herald_ref_cset default ""; else herald_ref_cset default "$1"; fi
  REF_LAST=""; blog "refresh: 默认规格 $1"; echo "ok refresh default $1"
}
heraldp_ref_sub_app() {
  herald_ref_pkg_ok "$1" || { echo "err refresh 用法: refresh app <包名> <auto|Hz|最小-最大|off>"; return; }
  if [ "$2" = off ]; then herald_ref_cset "app.$1" ""; REF_LAST=""; blog "refresh: 删规则 $1"; echo "ok refresh app $1 off"; return; fi
  herald_ref_spec_ok "$2" || { echo "err refresh 规格不对: $2(auto|Hz|最小-最大|off,档位见 refresh modes)"; return; }
  herald_ref_cset "app.$1" "$2"; REF_LAST=""; blog "refresh: 规则 $1=$2"; echo "ok refresh app $1 $2"
}
heraldp_ref_sub_apps() {
  echo "ok refresh apps"
  [ -f "$REF_CONF" ] && while IFS= read -r _l; do case "$_l" in app.*=*) _k=${_l#app.}; echo "${_k%%=*}=${_k#*=}" ;; esac; done < "$REF_CONF"
}
heraldp_ref_sub_battery() {
  if [ "$1" = off ]; then herald_ref_cset battery ""; REF_LAST=""; echo "ok refresh battery off"; return; fi
  herald_int_in "$1" 1 99 && herald_ref_spec_ok "$2" || { echo "err refresh 用法: refresh battery <1-99> <Hz|最小-最大> 或 refresh battery off"; return; }
  [ "$2" = auto ] && { echo "err refresh 封顶规格要写具体数值"; return; }
  herald_ref_cset battery "$1:$2"; REF_LAST=""; blog "refresh: 低电量 <$1% 封顶 $2"; echo "ok refresh battery $1 $2"
}
