# perf/game-boost 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/perf-game.sh)。命令本身是 game(由 game-mode/foreground-trigger 转发)。
heraldctl_help_game_perf() {
  cat <<'EOT'
  game perfprofile <performance|powersave|balanced>  名单应用在前台时用的性能档(默认 performance),离开后恢复进入前的设置
EOT
}
