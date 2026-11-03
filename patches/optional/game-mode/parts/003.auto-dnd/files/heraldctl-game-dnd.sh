# game-mode/auto-dnd 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/game-dnd.sh)。命令本身是 game(由 game-mode/foreground-trigger 转发)。
heraldctl_help_game_dnd() {
  cat <<'EOT'
  game dndmode <priority|none|alarms>  进入游戏时开哪种勿扰(默认 priority);本来就是勿扰则不改,退出时也保持
EOT
}
