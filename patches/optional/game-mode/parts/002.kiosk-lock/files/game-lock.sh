# game-mode/kiosk-lock 的 broker 插件(装在 /system/etc/herald_payload/plugins/game-lock.sh)。game-mode/foreground-trigger 的钩子 "lock"。
# 进入名单应用时:用 `cmd statusbar send-disable-flag` 禁掉主页手势/导航、最近任务、助手手势、下拉通知栏和快捷设置;
# 离开时 `send-disable-flag none` 恢复。(StatusBarShellCommand 用的是静态 token,flag 记在 system_server 里,
# 命令进程退出后依然有效,重启后清零。)
# 退出途径(应用里按不出来,必须用下面之一):
#   1. 音量键组合(默认 音量上、下、上、下、上、下,5 秒内按完;U=音量上 D=音量下)——后台常驻读 getevent 的按键事件;
#   2. heraldctl game release / 前端发 game release(adb 或前端);
#   3. 应用自己退出/崩溃(前台换了,3 秒后自动解锁);
#   4. 电源键长按菜单里重启(flag 重启后清零)。
# 命令:
#   game flags <flag…|default>    要禁用的 flag(默认 search home recents notification-peek statusbar-expansion notification-shade quick-settings)
#   game combo <UD…|default>      退出组合,4~12 个字母,只能 U / D
GAME_LOCK_FLAGS_DEFAULT="search home recents notification-peek statusbar-expansion notification-shade quick-settings"
GAME_LOCK_COMBO_DEFAULT=UDUDUD
GAME_LOCK_STATE=$STATE/game-lock.state     # 锁着时存在,内容 = 实际被接受的 flag;boot 时靠它判断要不要收拾
GAME_HOOKS="${GAME_HOOKS:-} lock"
GC_BUF=""; GC_T0=0
herald_game_combo_feed() {          # $1 字母 $2 当前秒 $3 组合 $4 窗口秒;组合凑齐返回 0
  if [ -n "$GC_BUF" ] && [ $(($2 - GC_T0)) -gt "$4" ]; then GC_BUF=""; fi
  [ -n "$GC_BUF" ] || GC_T0=$2
  GC_BUF="$GC_BUF$1"
  _glen=${#3}
  while [ ${#GC_BUF} -gt "$_glen" ]; do GC_BUF=${GC_BUF#?}; done
  [ "$GC_BUF" = "$3" ] && { GC_BUF=""; return 0; }
  return 1
}
herald_game_lock_flags() { _glf=$(herald_game_cget lock.flags); echo "${_glf:-$GAME_LOCK_FLAGS_DEFAULT}"; }
herald_game_lock_combo() { _glc=$(herald_game_cget lock.combo); echo "${_glc:-$GAME_LOCK_COMBO_DEFAULT}"; }
heraldp_game_enter_lock() {
  _gla=""
  for _glf1 in $(herald_game_lock_flags); do
    _glo=$(herald_game_sysq "$GAME_BIN/cmd" statusbar send-disable-flag $_gla $_glf1)
    case "$_glo" in *nrecognized*|*nknown*|*rror*|*xception*|*nvalid*) blog "game: lock 跳过 flag $_glf1: $(echo "$_glo" | head -1)" ;; *) _gla="$_gla $_glf1" ;; esac
  done
  if [ -z "$_gla" ]; then blog "game: lock 没有任何 flag 被接受"; herald_game_sysq "$GAME_BIN/cmd" statusbar send-disable-flag none >/dev/null; return 1; fi
  echo "${_gla# }" > "$GAME_LOCK_STATE"
  blog "game: lock 已禁用 ${_gla# }"
  return 0
}
heraldp_game_exit_lock() {
  _glo=$(herald_game_sysq "$GAME_BIN/cmd" statusbar send-disable-flag none)
  case "$_glo" in *nrecognized*|*rror*|*xception*) _glo2=$(herald_game_sysq "$GAME_BIN/cmd" statusbar send-disable-flag none); blog "game: lock 恢复第一次失败,重试: $(echo "$_glo2" | head -1)" ;; esac
  rm -f "$GAME_LOCK_STATE"; return 0
}
heraldp_game_boot_lock() { [ -f "$GAME_LOCK_STATE" ] && { blog "game: lock 上次没收拾干净,现在恢复"; heraldp_game_exit_lock; }; return 0; }
heraldp_game_watch_lock() {         # 常驻:读 getevent 的按键,音量键凑成组合就放"解除"标记
  "$GAME_BIN/getevent" -q 2>/dev/null | while read -r _ga _gb2 _gc2 _gd; do
    case "$_ga" in *:) _gt=$_gb2; _gk=$_gc2; _gv=$_gd ;; *) _gt=$_ga; _gk=$_gb2; _gv=$_gc2 ;; esac
    [ "$_gt" = 0001 ] && [ "$_gv" = 00000001 ] || continue
    case "$_gk" in 0073) _gL=U ;; 0072) _gL=D ;; *) continue ;; esac
    [ -f "$GAME_STATE" ] || continue
    if herald_game_combo_feed "$_gL" "${HERALD_GAME_NOW:-$(date +%s)}" "$(herald_game_lock_combo)" 5; then : > "$W/game_release"; blog "game: 音量组合触发解除"; fi
  done
}
heraldp_game_status_lock() {
  echo "lock_flags=$(herald_game_lock_flags)"
  echo "lock_combo=$(herald_game_lock_combo)"
  [ -f "$GAME_LOCK_STATE" ] && echo "lock_applied=$(cat "$GAME_LOCK_STATE")" || echo "lock_applied="
}
heraldp_game_sub_flags() {
  case "$*" in "") echo "err game 用法: game flags <flag…|default>"; return ;; default) herald_game_cset lock.flags ""; echo "ok game flags default"; return ;; esac
  for _glf1 in "$@"; do case "$_glf1" in *[!a-z0-9-]*) echo "err game flag 只能是小写字母数字和减号: $_glf1"; return ;; esac; done
  herald_game_cset lock.flags "$*"; echo "ok game flags $*"
}
heraldp_game_sub_combo() {
  case "$1" in "") echo "err game 用法: game combo <UD…|default>"; return ;; default) herald_game_cset lock.combo ""; echo "ok game combo default"; return ;; esac
  case "$1" in *[!UD]*) echo "err game 组合只能由 U(音量上)和 D(音量下)组成"; return ;; esac
  [ ${#1} -ge 4 ] && [ ${#1} -le 12 ] || { echo "err game 组合长度要 4~12 个"; return; }
  herald_game_cset lock.combo "$1"; echo "ok game combo $1"
}
