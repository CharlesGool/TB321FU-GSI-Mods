# game-mode/foreground-trigger 的 heraldctl 插件(装在 /system/etc/heraldctl.d/game.sh)。用到 heraldctl 的 send、die。
# 子命令都由 broker 端分发;帮助 = 这里的几行 + 已装钩子模块(kiosk-lock、auto-dnd)定义的 heraldctl_help_game_<名字>。
heraldctl_help_game() {
  cat <<'EOT'
游戏模式(名单里的应用在前台时:锁住退出途径、自动开勿扰,离开后恢复)
  game status                   状态:开关、后台进程、前台应用、当前是否生效
  game add <包名> [钩子名…]      加入名单(不写钩子名 = 所有钩子;例 game add com.tencent.tmgp.sgame lock dnd)
  game remove <包名>            移出名单
  game list                     名单
  game on | game off            总开关
  game release                  立刻解除本次(应用还在前台也不再锁;离开再进来才重新生效)
  game debounce <秒>            离开名单应用多久后才算真离开(默认 0 = 立刻)
EOT
  type heraldctl_help_game_lock >/dev/null 2>&1 && heraldctl_help_game_lock
  type heraldctl_help_game_dnd >/dev/null 2>&1 && heraldctl_help_game_dnd
  type heraldctl_help_game_perf >/dev/null 2>&1 && heraldctl_help_game_perf
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_game"

heraldctl_cmd_game() {
  [ -n "$1" ] || die "用法: heraldctl game <子命令> …(看 heraldctl help 的"游戏模式"一节)"
  send "game $*"
}
