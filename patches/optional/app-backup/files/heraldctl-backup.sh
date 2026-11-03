# app-backup 的 heraldctl 插件(装在 /system/etc/heraldctl.d/backup.sh)。用到 heraldctl 的 send、die。
heraldctl_help_backup() {
  cat <<'EOT'
App 备份 / 还原(apk 含 split + 数据,备份到指定目录;只做用户 0)
  backup [status]                           默认目录、备份个数、最近任务
  backup dest [目录]                         看 / 设默认目录(默认 /sdcard/HeraldBackup)
  backup app <包名> [目录] [--no-apk] [--no-data] [--ext]   备份(后台跑)
  backup restore <包名> [目录] [--reinstall]  还原;应用没装就先装 apk
  backup list [目录]                         目录里的备份
  backup delete <包名> [目录]                 删备份
  backup job [号]                            任务状态
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_backup"

heraldctl_cmd_backup() {
  send "backup $*"
}
