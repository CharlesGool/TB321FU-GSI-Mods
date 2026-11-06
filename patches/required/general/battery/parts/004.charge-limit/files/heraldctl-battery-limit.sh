# battery/charge-limit 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/battery-limit.sh)。
heraldctl_help_battery_limit() {
  cat <<'EOT'
  battery limit status          充电上限现在的状态
  battery limit <20-100> [回充比例]  电量到上限停充,低于 上限x回充比例% 才重新充(回充比例默认 95)
  battery limit off             取消(上限 100)
EOT
}
