# navbar-hide 的 broker 插件(装在 /system/etc/herald_payload/plugins/navbar.sh,由 herald-start.sh source)。
# 提供 broker 命令 navbar hide|show|status,以及空闲时的导航模式守护。用到 herald-start.sh 的 herald_sys、blog、$W、$STATE。
#
# 导航栏隐藏(像国产系统那样:不画提示线、App 不给底部让高度,手势照旧)
#   底部有两种:低 DPI(平板模式)是启动器的任务栏,高 DPI(手机模式)是 SystemUI 的导航栏。
#   /product/overlay/OmkNavHide{Fw,SysUI,Launcher}/ 三个非静态 RRO 覆盖两种(源码 patches/required/tangorpro/tangorpro_ap3a.241005.015/navbar-hide/overlay-*/)。
#   每个 APK 必须单独一个目录:同一目录里的多个 APK 会被当成一个包的拆分包,包名不同就整目录作废(V65 真机)。
#     com.omk.navhide.android  框架 navigation_bar_height 等 = 0(手机模式给 App 的占位高度)
#     com.omk.navhide.systemui SystemUI 手势提示线颜色全透明
#     com.omk.navhide.launcher 任务栏收起高度 = 0(平板模式给 App 的占位高度),收起时的小白条全透明
#   手势判定区(navigation_bar_gesture_height)不动,所以上滑回桌面/多任务、侧滑返回、底部横滑切 App 都照旧。
#   用户意愿记在 $NAV_PREF;只在手势导航下生效,三键导航时自动撤掉(三键按钮还得占位),切回手势再自动打开。
NAV_PREF=$STATE/navbar_hide
NAV_APPLIED=$STATE/navbar_applied
NAV_PKGS="com.omk.navhide.android com.omk.navhide.systemui com.omk.navhide.launcher"
NAV_BUSY=$STATE/navbar_busy   # 切换进行中的标记:导航模式会被短暂切一下,守护这时别误判成"用户切到了三键"
herald_nav_mode() { herald_sys /system/bin/settings get secure navigation_mode | tr -d '\r\n '; }   # 0 三键 1 两键 2 手势
herald_nav_bar() {   # 现在底部是谁画的
  herald_sys /system/bin/dumpsys window windows > "$W/herald_t9"
  if grep -q 'NavigationBar0' "$W/herald_t9"; then echo navbar
  elif grep -q 'Taskbar' "$W/herald_t9"; then echo taskbar
  else echo none; fi
  rm -f "$W/herald_t9"
}
# 现在是不是手机模式:最小宽度 < 600dp 时系统用 SystemUI 自己的导航栏,否则用启动器的任务栏。
#   用 `wm size` 和 `wm density`(有 Override 就用 Override,即"显示大小"调过的值)算,不依赖 dumpsys。
#   输出 sw=<dp>,返回 0 = 手机模式,1 = 平板模式,2 = 读不出来。
herald_nav_phone() {
  _sz=$(herald_sys /system/bin/wm size); _dn=$(herald_sys /system/bin/wm density)
  _wh=$(echo "$_sz" | sed -n 's/.*Override size: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | head -1)
  [ -n "$_wh" ] || _wh=$(echo "$_sz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | head -1)
  _d=$(echo "$_dn" | sed -n 's/.*Override density: *\([0-9]*\).*/\1/p' | head -1)
  [ -n "$_d" ] || _d=$(echo "$_dn" | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | head -1)
  set -- $_wh
  case "$1$2$_d" in ""|*[!0-9]*) _sw=?; return 2 ;; esac
  [ "$_d" -gt 0 ] || { _sw=?; return 2; }
  _m=$1; [ "$2" -lt "$_m" ] && _m=$2
  _sw=$((_m * 160 / _d))
  [ "$_sw" -lt 600 ]
}
# 导航栏现在给应用留的面积(像素²):读 dumpsys window 里 type=navigationBars 的 frame。隐藏时是 0。读不出来输出 -1。
herald_nav_inset() {
  herald_sys /system/bin/dumpsys window > "$W/herald_t11"
  _fl=$(grep -m1 -o 'type=navigationBars frame=\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' "$W/herald_t11" 2>/dev/null)
  rm -f "$W/herald_t11"
  [ -n "$_fl" ] || { echo -1; return; }
  set -- $(echo "$_fl" | sed 's/.*frame=\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/')
  echo $(( ($3 - $1) * ($4 - $2) ))
}
# 不杀 SystemUI,让它自己重建导航栏:把导航模式覆盖层 手势→三键→手势 快速切一遍。这是系统自己切换导航模式走的路径,
#   SystemUI 会当场重建导航栏(重新读 navigation_bar_height、提示线颜色),状态栏和通知不受影响。
herald_nav_refresh() {
  _gp=com.android.internal.systemui.navbar.gestural; _tp=com.android.internal.systemui.navbar.threebutton
  herald_sys /system/bin/cmd overlay enable-exclusive --user 0 --category "$_tp" >/dev/null
  herald_sys /system/bin/cmd overlay enable-exclusive --user 0 --category "$_gp" >/dev/null
  # 确认真的回到了手势导航(navigation_mode=2):连着切几次偶尔停在三键,要补一次;补不回来就记日志,别假装成功
  _k=0
  while [ "$_k" -lt 6 ]; do
    [ "$(herald_nav_mode)" = 2 ] && return 0
    herald_sys /system/bin/cmd overlay enable-exclusive --user 0 --category "$_gp" >/dev/null
    sleep 0.5; _k=$((_k + 1))
  done
  blog "navbar: 导航模式没能切回手势(navigation_mode=$(herald_nav_mode))"
}
# 手机模式下让导航栏的改动生效。$1 = enable(要隐藏,应该读到 0) | disable(要显示,应该读到非 0)
#   先试 herald_nav_refresh,轮询最多 4 秒看 herald_nav_inset 是不是变成了该有的样子;没变、或者读不出来,就回落到重启 SystemUI。
herald_nav_apply_phone() {
  herald_nav_refresh
  _try=0
  while [ "$_try" -lt 8 ]; do
    sleep 0.5; _ia=$(herald_nav_inset); _try=$((_try + 1))
    if [ "$1" = enable ] && [ "$_ia" = 0 ]; then _rs="$_rs (SystemUI 没重启:导航栏已重建)"; return 0; fi
    if [ "$1" = disable ] && [ "$_ia" != 0 ] && [ "$_ia" != -1 ]; then _rs="$_rs (SystemUI 没重启:导航栏已重建)"; return 0; fi
    [ "$_ia" = -1 ] && break      # 读不出来就别等了,没法验证
  done
  _pp=$(pidof com.android.systemui 2>/dev/null); [ -n "$_pp" ] && kill $_pp
  _rs="$_rs systemui(轻量重建没生效,inset=$_ia,已回落重启)"
}
herald_nav_set() {   # $1 = enable | disable;失败的包每个打一行 fail
  _nf=0
  for _p in $NAV_PKGS; do
    _o=$(herald_sys /system/bin/cmd overlay "$1" --user 0 "$_p")
    case "$_o" in *rror*|*xception*|*nknown*|*ailed*) _nf=$((_nf+1)); echo "fail $1 $_p: $(echo "$_o" | head -2 | tr '\n' ' ')" ;; esac
    [ "$1" = enable ] && herald_sys /system/bin/cmd overlay set-priority "$_p" highest >/dev/null
  done
  # 三个全失败(多半是 overlay 根本没被系统注册,见 V65)就什么都没变,不用重启任何东西
  [ "$_nf" -ge 3 ] && return $_nf
  # 让改动生效:任务栏在启动器进程里,杀掉后系统马上拉起。手机模式(显示大小调大、最小宽度 < 600dp)下导航栏和提示线
  #   是 SystemUI 画的,要让它重建:先轻量重建(herald_nav_apply_phone),验证不过才重启 SystemUI。
  #   判断"是不是手机模式"用两条独立的线索,任何一条说是、或者读不出来,就按手机模式处理:
  #     1) 按显示大小/密度算出的最小宽度 < 600dp    2) dumpsys window 里有 NavigationBar0
  #   平板模式(两条线索都明确说不是)SystemUI 没有导航栏,不用动它。
  touch "$NAV_BUSY"
  _bar=$(herald_nav_bar)
  herald_nav_phone; _ph=$?
  # 手机模式(底部是 SystemUI 的导航栏)启动器没有任务栏,不用杀它;杀它又同时切导航模式,两边抢着重建,连着操作容易卡出坏状态
  _rs=""
  if [ "$_bar" = navbar ] && [ "$_ph" = 0 ]; then :
  else
    _pp=$(pidof com.google.android.apps.nexuslauncher 2>/dev/null); [ -n "$_pp" ] && kill $_pp
    _rs=launcher
  fi
  if [ "$_bar" = navbar ] || [ "$_ph" != 1 ]; then herald_nav_apply_phone "$1"; fi
  # 等 SystemUI / 启动器重建稳定再放行,下一条命令(或守护)不会叠在重建中间
  sleep 2
  rm -f "$NAV_BUSY"
  blog "navbar: $1 后重启 $_rs(bar=$_bar 手机模式=$_ph sw=${_sw}dp)"
  return $_nf
}
herald_nav_guard() {   # 空闲时每 5 秒查一次:意愿 + 导航模式 → 该开就开、该撤就撤
  [ -f "$NAV_BUSY" ] && [ -z "$(find "$NAV_BUSY" -mmin +1 2>/dev/null)" ] && return 0   # 正在切换,别插手(超过 1 分钟的残留不算)
  [ -f "$NAV_PREF" ] || [ -f "$NAV_APPLIED" ] || return 0
  _m=$(herald_nav_mode)
  case "$_m" in [0-9]) ;; *) return 0 ;; esac   # 开机早期 settings 还读不到,别误撤
  if [ -f "$NAV_PREF" ] && [ "$_m" = 2 ]; then
    [ -f "$NAV_APPLIED" ] && return 0
    herald_nav_set enable > "$W/herald_t10"; touch "$NAV_APPLIED"; blog "navbar: 手势导航,自动隐藏 $(tr '\n' ' ' < "$W/herald_t10")"
  else
    [ -f "$NAV_APPLIED" ] || return 0
    herald_nav_set disable > "$W/herald_t10"; rm -f "$NAV_APPLIED"; blog "navbar: navigation_mode=$_m,自动恢复 $(tr '\n' ' ' < "$W/herald_t10")"
  fi
  rm -f "$W/herald_t10"
}
herald_navbar() {   # $1 = hide | show | status
  case "$1" in
    hide)
      touch "$NAV_PREF"; _m=$(herald_nav_mode)
      if [ "$_m" != 2 ]; then
        echo "ok navbar hide pending"
        echo "已记下;当前 navigation_mode=$_m 不是手势导航,切到手势导航后自动隐藏"; return 0
      fi
      # 部分失败也记成"已做过",否则守护每 5 秒重试一次、每次都杀启动器;
      #   三个全失败 = 什么都没变,连意愿也撤掉,免得 status 显示 pref=hide 而栏没动(V65 报告)
      herald_nav_set enable > "$W/herald_t10"; _nr=$?
      if [ "$_nr" = 0 ]; then echo "ok navbar hidden"; touch "$NAV_APPLIED"
      elif [ "$_nr" -ge 3 ]; then echo "err navbar hide 三个 overlay 都没开成, 设置未保存"; rm -f "$NAV_PREF" "$NAV_APPLIED"
      else echo "err navbar hide"; touch "$NAV_APPLIED"; fi
      cat "$W/herald_t10"; rm -f "$W/herald_t10" ;;
    show)
      rm -f "$NAV_PREF"
      if herald_nav_set disable > "$W/herald_t10"; then echo "ok navbar shown"; else echo "err navbar show"; fi
      rm -f "$NAV_APPLIED"
      cat "$W/herald_t10"; rm -f "$W/herald_t10" ;;
    status)
      herald_sys /system/bin/cmd overlay list --user 0 > "$W/herald_t10"
      _st=""; for _p in $NAV_PKGS; do
        if grep -q "\[x\] $_p" "$W/herald_t10"; then _st="$_st ${_p##*.}=on"
        elif grep -q "$_p" "$W/herald_t10"; then _st="$_st ${_p##*.}=off"
        else _st="$_st ${_p##*.}=missing"; fi
      done
      case "$_st" in *=off*|*=missing*) _h=shown ;; *) _h=hidden ;; esac
      echo "ok navbar $_h"
      [ -f "$NAV_PREF" ] && echo "pref=hide" || echo "pref=show"
      echo "navigation_mode=$(herald_nav_mode)(0 三键 1 两键 2 手势)"
      echo "overlays:$_st"
      echo "bar=$(herald_nav_bar)(taskbar = 平板模式/启动器任务栏, navbar = 手机模式/SystemUI 导航栏)"
      echo "density=$(herald_sys /system/bin/wm density | tr '\n' ' ')"
      rm -f "$W/herald_t10" ;;
    *) echo "err navbar 用法: navbar hide|show|status" ;;
  esac
}

# 注册给 broker
heraldp_cmd_navbar() { herald_navbar "$1"; }
HERALDP_IDLE="${HERALDP_IDLE:-} herald_nav_guard"
