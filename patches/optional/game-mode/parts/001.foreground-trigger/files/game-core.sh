# game-mode/foreground-trigger 的 broker 插件(装在 /system/etc/herald_payload/plugins/game-core.sh)。
# 游戏模式的核心:维护"游戏名单",盯着前台应用;进入名单里的应用时对每个已装的"钩子"调 enter,离开时调 exit。
# 钩子是别的模块(game-mode/kiosk-lock、game-mode/auto-dnd …):把自己的名字追加进 GAME_HOOKS,再定义
#   heraldp_game_enter_<名字> <包名>   进入时调(返回 0 = 做成了,记入"本次生效的钩子")
#   heraldp_game_exit_<名字>           离开时调
#   heraldp_game_boot_<名字>           (可选)后台进程启动时调:把上次异常中断留下的东西收拾掉
#   heraldp_game_watch_<名字>          (可选)要一个常驻的监听就定义它,后台进程会把它放到后台跑
#   heraldp_game_status_<名字>         (可选)往 `game status` 里加几行 键=值
#   heraldp_game_sub_<子命令>          (可选)给 `game` 命令加子命令
# 命令:
#   game add <包名> [钩子名…]    加入名单;不写钩子名 = 所有钩子都用,写了就只用这几个
#   game remove <包名> | game list | game on | game off | game status
#   game release                 立刻解除本次(名单里的应用还在前台也不再锁/不再开勿扰,离开再进来才重新生效)
#   game debounce <秒>           离开名单应用多久后才算真离开(V84 起默认 0 = 立刻;权限弹窗/安装器/系统界面这类"一闪而过"的前台不算离开,不靠防抖)
# 后台进程(V84 起每 0.25 秒判断一次,前台没变时不起任何子进程):前台应用靠 logcat 的 events 缓冲区(wm_set_resumed_activity/wm_focused_app,
#   进程里没有轮询);另外每 5 秒用 dumpsys window 对一次,防监听挂掉或漏事件。
#   所有改系统的动作都只在这个后台进程里做;命令处理(主 shell)只改配置文件和放"解除"标记,两边不抢 $W 下的临时文件。
GAME_BIN=${HERALD_GAME_BIN:-/system/bin}
GAME_CONF=$STATE/game.conf       # enabled=0|1(默认 1)、app.<包名>=*|钩子,钩子、debounce=<秒>、各钩子自己的键
GAME_STATE=$STATE/game.state     # 生效中:active=<包名> hooks=<钩子> since=<秒>;没有这个文件 = 没有生效
GAME_HOOKS=${GAME_HOOKS:-}       # 不重置:插件按字母序加载,别的模块可能已经追加过了
herald_game_cget() { _gv=""; [ -f "$GAME_CONF" ] && while IFS= read -r _gl; do case "$_gl" in "$1="*) _gv=${_gl#*=} ;; esac; done < "$GAME_CONF"; echo "$_gv"; }
herald_game_cset() {                # $1 键 $2 值;值为空 = 删掉这个键
  { [ -f "$GAME_CONF" ] && while IFS= read -r _gl; do case "$_gl" in "$1="*) ;; *) echo "$_gl" ;; esac; done < "$GAME_CONF"
    [ -n "$2" ] && echo "$1=$2"; } > "$GAME_CONF.new" 2>/dev/null
  mv -f "$GAME_CONF.new" "$GAME_CONF" 2>/dev/null
  : > "$W/game_cfgdirty" 2>/dev/null   # 配置变了,后台进程要重新判断一次(前台没变也要)
}
herald_game_sysq() {                # 跑系统命令(binder 那头不能用 herald 域的管道,所以经文件转出);只给后台进程用,临时文件名不和 herald_sys 重
  ( unset LD_LIBRARY_PATH; "$@" >"$W/game_t1" 2>&1 </dev/null ); _gsrc=$?
  cat "$W/game_t1" 2>/dev/null; rm -f "$W/game_t1"; return $_gsrc
}
herald_game_pkg_ok() { case "$1" in ""|*[!A-Za-z0-9._]*|.*|*..*|*.) return 1 ;; esac; return 0; }
herald_game_opt_has() {             # $1 = "*" 或逗号分隔的钩子名;$2 要找的钩子
  case ",$1," in *",*,"*|*",$2,"*) return 0 ;; esac; return 1
}
herald_game_hook_known() { for _gk in $GAME_HOOKS; do [ "$_gk" = "$1" ] && return 0; done; return 1; }
herald_game_alive() { [ -f "$W/game.pid" ] && kill -0 "$(cat "$W/game.pid" 2>/dev/null)" 2>/dev/null; }
herald_game_napps() { _gn2=0; [ -f "$GAME_CONF" ] && _gn2=$(grep -c '^app\.' "$GAME_CONF" 2>/dev/null); echo "${_gn2:-0}"; }

# ---- 前台应用 ----
herald_game_parse_event() {         # logcat -v brief 的一行 -> 包名(不是事件/不是 Activity 就返回 1)
  case "$1" in *wm_set_resumed_activity*|*wm_focused_app*) ;; *) return 1 ;; esac
  _gb=${1#*\[}; [ "$_gb" != "$1" ] || return 1
  _gb=${_gb%%\]*}                # 0,com.pkg/.Act,reason
  _gb=${_gb#*,}                  # com.pkg/.Act,reason
  _gc=${_gb%%,*}; _gc=$(echo "$_gc" | tr -d '"')
  case "$_gc" in */*) echo "${_gc%%/*}" ;; *) return 1 ;; esac
}
herald_game_putfg() { echo "$1" > "$W/game_fg.n" 2>/dev/null && mv -f "$W/game_fg.n" "$W/game_fg"; }
herald_game_poll_fg() {             # 用 dumpsys window 对一次前台应用(mCurrentFocus,没有就看 mFocusedApp)
  herald_game_sysq "$GAME_BIN/dumpsys" window > "$W/game_w" 2>/dev/null
  _gl=$(grep -m1 'mCurrentFocus=Window' "$W/game_w")
  case "$_gl" in *null*|"") _gl=$(grep -m1 'mFocusedApp=' "$W/game_w") ;; esac
  rm -f "$W/game_w"
  for _gt in $_gl; do case "$_gt" in */*) _gp=${_gt%%/*}; herald_game_putfg "${_gp##*[ \{]}"; return ;; esac; done
}
herald_game_watch_fg() {            # 常驻:读 logcat 事件,写 $W/game_fg
  "$GAME_BIN/logcat" -b events -T 1 -v brief wm_set_resumed_activity:I wm_focused_app:I '*:S' 2>/dev/null | while IFS= read -r _gl; do
    _gp=$(herald_game_parse_event "$_gl") && [ -n "$_gp" ] && herald_game_putfg "$_gp"
  done
}

# ---- 进入/离开 ----
herald_game_enter() {               # $1 包名 $2 选项(* 或钩子,钩子)
  _ghs=""
  for _gh in $GAME_HOOKS; do
    herald_game_opt_has "$2" "$_gh" || continue
    type "heraldp_game_enter_$_gh" >/dev/null 2>&1 || continue
    "heraldp_game_enter_$_gh" "$1" && _ghs="$_ghs $_gh"
  done
  echo "active=$1" > "$GAME_STATE"; echo "hooks=$(echo $_ghs | tr ' ' ',')" >> "$GAME_STATE"; echo "since=$(date +%s)" >> "$GAME_STATE"
  blog "game: 进入 $1 (${_ghs# })"
  # V89:记下游戏主进程 pid,tick 每拍读它的 oom_score_adj(内建 read,不起子进程):离开前台时它马上从 0 变大,
  #   不用等窗口事件或 5 秒一次的 dumpsys(V86 真机:进入快、退出慢)
  GAME_PID=$("$GAME_BIN/pidof" "$1" 2>/dev/null | cut -d' ' -f1); GAME_ADJSEEN=0
}
herald_game_exit() {
  _gx=""; [ -f "$GAME_STATE" ] && while IFS= read -r _gl; do case "$_gl" in hooks=*) _gx=${_gl#hooks=} ;; esac; done < "$GAME_STATE"
  # 先倒着收:后进的钩子先退
  _grev=""; for _gh in $(echo "$_gx" | tr ',' ' '); do _grev="$_gh $_grev"; done
  for _gh in $_grev; do type "heraldp_game_exit_$_gh" >/dev/null 2>&1 && { "heraldp_game_exit_$_gh" || blog "game: 钩子 $_gh 退出失败"; }; done
  rm -f "$GAME_STATE"; GAME_PID=""; GAME_ADJSEEN=0; blog "game: 离开"
}
herald_game_active() { _ga=""; [ -f "$GAME_STATE" ] && while IFS= read -r _gl; do case "$_gl" in active=*) _ga=${_gl#active=} ;; esac; done < "$GAME_STATE"; echo "$_ga"; }
GAME_MISS=0; GAME_REL=""; GAME_LASTFG="-"; GAME_TPS=${HERALD_GAME_TPS:-4}; GAME_PID=""; GAME_ADJSEEN=0
GAME_PROC=${HERALD_GAME_PROC:-/proc}
# 这些前台只是"一闪而过"的系统界面:游戏生效中碰到它们不算离开、也不计防抖
GAME_TRANSIENT=" com.google.android.permissioncontroller com.android.permissioncontroller com.google.android.packageinstaller com.android.packageinstaller com.android.systemui "
herald_game_tick() {                # 后台进程每 1/GAME_TPS 秒调一次
  # 生效中:游戏主进程不在前台(oom_score_adj 不是 0)或进程没了,立刻用 dumpsys 对一次前台;同一个 adj 只对一次
  if [ -n "$GAME_PID" ]; then
    _gadj=""; read -r _gadj < "$GAME_PROC/$GAME_PID/oom_score_adj" 2>/dev/null
    if [ "$_gadj" = 0 ]; then GAME_ADJSEEN=0
    elif [ "$_gadj" != "$GAME_ADJSEEN" ]; then
      GAME_ADJSEEN=${_gadj:-gone}
      if [ -z "$_gadj" ]; then herald_game_putfg "-gone-"; else herald_game_poll_fg; fi
    fi
  fi
  _gcur=""; [ -r "$W/game_fg" ] && read -r _gcur < "$W/game_fg"   # read 是内建,不起子进程
  # 快路径:前台没变、没有待办的解除/配置变化/防抖计数,什么都不用做
  if [ "$_gcur" = "$GAME_LASTFG" ] && [ "$GAME_MISS" = 0 ] && [ ! -e "$W/game_release" ] && [ ! -e "$W/game_cfgdirty" ]; then return 0; fi
  rm -f "$W/game_cfgdirty"
  _gact=$(herald_game_active)
  if [ -f "$W/game_release" ]; then
    rm -f "$W/game_release"
    if [ -n "$_gact" ]; then herald_game_exit; GAME_REL=$_gact; _gact=""; blog "game: 手动解除 $GAME_REL"; fi
  fi
  [ -n "$GAME_REL" ] && [ "$_gcur" != "$GAME_REL" ] && [ -n "$_gcur" ] && GAME_REL=""   # 离开过那个应用,解除作废
  [ -n "$_gcur" ] || return 0                       # 前台未知:不动
  GAME_LASTFG=$_gcur
  _gopt=$(herald_game_cget "app.$_gcur")
  if [ -n "$_gact" ]; then
    if [ "$_gcur" = "$_gact" ]; then GAME_MISS=0; return 0; fi
    if [ -n "$_gopt" ]; then herald_game_exit; GAME_MISS=0; herald_game_enter "$_gcur" "$_gopt"; return 0; fi   # 直接换到另一个名单应用
    case "$GAME_TRANSIENT" in *" $_gcur "*) GAME_LASTFG="-"; return 0 ;; esac   # 权限弹窗之类:不算离开
    GAME_MISS=$((GAME_MISS + 1))
    _gdb=$(herald_game_cget debounce); herald_int_in "$_gdb" 0 60 || _gdb=0
    if [ "$GAME_MISS" -ge $((_gdb * GAME_TPS)) ]; then herald_game_exit; GAME_MISS=0; fi
    return 0
  fi
  GAME_MISS=0
  [ -n "$_gopt" ] && [ "$_gcur" != "$GAME_REL" ] && herald_game_enter "$_gcur" "$_gopt"
  return 0
}
herald_game_cleanup() {
  [ -f "$GAME_STATE" ] && herald_game_exit
  [ -n "${GAME_KIDS:-}" ] && kill $GAME_KIDS 2>/dev/null
  pkill -f "logcat -b events -T 1 -v brief wm_set_resumed" 2>/dev/null
  rm -f "$W/game.pid" "$W/game_fg"
}
herald_game_run() {                 # 后台进程本体
  trap 'herald_game_cleanup; exit 0' TERM INT
  rm -f "$W/game_fg" "$W/game_release"
  for _gh in $GAME_HOOKS; do type "heraldp_game_boot_$_gh" >/dev/null 2>&1 && "heraldp_game_boot_$_gh"; done
  rm -f "$GAME_STATE"
  GAME_KIDS=""
  herald_game_watch_fg & GAME_KIDS="$!"
  for _gh in $GAME_HOOKS; do type "heraldp_game_watch_$_gh" >/dev/null 2>&1 && { "heraldp_game_watch_$_gh" & GAME_KIDS="$GAME_KIDS $!"; }; done
  herald_game_poll_fg
  _gn=0
  while [ "$(herald_game_cget enabled)" != 0 ] && [ "$(herald_game_napps)" != 0 ]; do
    _gn=$((_gn + 1)); [ $((_gn % (GAME_TPS * 5))) = 0 ] && herald_game_poll_fg
    herald_game_tick
    sleep "${HERALD_GAME_TICK:-0.25}"
  done
  herald_game_cleanup
}
herald_game_ensure() {              # 该跑就拉起后台进程;不该跑又在跑就让它退出
  if [ "$(herald_game_cget enabled)" != 0 ] && [ "$(herald_game_napps)" != 0 ]; then
    herald_game_alive && return 0
    ( herald_game_run ) >/dev/null 2>&1 </dev/null &
    echo "$!" > "$W/game.pid"
  fi
}
heraldp_game_idle() { herald_game_ensure; }
HERALDP_IDLE="${HERALDP_IDLE:-} heraldp_game_idle"
# broker 重启时,上一个后台进程可能还在(同一个 W 目录):不管它还在不在,先让它退
[ -f "$W/game.pid" ] && { kill "$(cat "$W/game.pid" 2>/dev/null)" 2>/dev/null; rm -f "$W/game.pid"; }

heraldp_cmd_game() {
  set -- $1
  _sub=${1:-}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err game 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_game_sub_$_sub" >/dev/null 2>&1; then "heraldp_game_sub_$_sub" "$@"
  else echo "err game 没有子命令 $_sub(装了哪些见 heraldctl help)"; fi
}
heraldp_game_sub_add() {
  herald_game_pkg_ok "$1" || { echo "err game 用法: game add <包名> [钩子名…]"; return; }
  _gpk=$1; shift; _gopts=""
  for _gh in "$@"; do
    herald_game_hook_known "$_gh" || { echo "err game 没有钩子 $_gh(已装:${GAME_HOOKS# })"; return; }
    _gopts="$_gopts,$_gh"
  done
  _gv=${_gopts#,}; herald_game_cset "app.$_gpk" "${_gv:-*}"
  herald_game_ensure; blog "game: 加入 $_gpk"
  echo "ok game add $_gpk $(herald_game_cget "app.$_gpk")"
}
heraldp_game_sub_remove() {
  herald_game_pkg_ok "$1" || { echo "err game 用法: game remove <包名>"; return; }
  [ -n "$(herald_game_cget "app.$1")" ] || { echo "err game $1 不在名单里"; return; }
  herald_game_cset "app.$1" ""; blog "game: 移出 $1"; echo "ok game remove $1"
}
heraldp_game_sub_list() {
  echo "ok game list"
  [ -f "$GAME_CONF" ] && while IFS= read -r _gl; do case "$_gl" in app.*=*) _gk=${_gl#app.}; echo "${_gk%%=*}=${_gk#*=}" ;; esac; done < "$GAME_CONF"
}
heraldp_game_sub_on()  { herald_game_cset enabled ""; herald_game_ensure; echo "ok game on"; }
heraldp_game_sub_off() { herald_game_cset enabled 0; echo "ok game off"; }   # 后台进程下一秒发现就会收拾现场并退出
heraldp_game_sub_debounce() {
  herald_int_in "$1" 0 60 || { echo "err game 用法: game debounce <0-60 秒>"; return; }
  herald_game_cset debounce "$1"; echo "ok game debounce $1"
}
heraldp_game_sub_release() {
  if [ -n "$(herald_game_active)" ]; then : > "$W/game_release"; blog "game: 收到解除请求"; echo "ok game release"
  else echo "ok game release nothing-active"; fi
}
heraldp_game_sub_status() {
  echo "ok game status"
  [ "$(herald_game_cget enabled)" = 0 ] && echo "enabled=off" || echo "enabled=on"
  if herald_game_alive; then echo "daemon=running"
  else
    echo "daemon=stopped"
    # 设计如此:名单为空或总开关关着时不起后台进程(省电);加第一个应用后 5 秒内自动拉起
    if [ "$(herald_game_cget enabled)" = 0 ]; then echo "daemon_reason=disabled"
    elif [ "$(herald_game_napps)" = 0 ]; then echo "daemon_reason=no-apps"
    else echo "daemon_reason=starting"; fi
  fi
  echo "hooks=$(echo $GAME_HOOKS | tr ' ' ',')"
  echo "apps=$(herald_game_napps)"
  echo "foreground=$(cat "$W/game_fg" 2>/dev/null)"
  echo "active=$(herald_game_active)"
  [ -f "$GAME_STATE" ] && while IFS= read -r _gl; do case "$_gl" in hooks=*) echo "active_hooks=${_gl#hooks=}" ;; esac; done < "$GAME_STATE"
  _gdb=$(herald_game_cget debounce); echo "debounce=${_gdb:-0}"
  for _gh in $GAME_HOOKS; do type "heraldp_game_status_$_gh" >/dev/null 2>&1 && "heraldp_game_status_$_gh"; done
}
