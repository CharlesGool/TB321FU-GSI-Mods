# game-mode/kiosk-lock 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/game-lock.sh)。命令本身是 game(由 game-mode/foreground-trigger 转发)。
heraldctl_help_game_lock() {
  cat <<'EOT'
  game flags <flag…|default>    锁定时要禁用的 flag(默认:search home recents notification-peek statusbar-expansion notification-shade quick-settings)
  game combo <UD…|default>      退出组合键,音量上=U 音量下=D,4~12 个,5 秒内按完(默认 UDUDUD)
EOT
}
