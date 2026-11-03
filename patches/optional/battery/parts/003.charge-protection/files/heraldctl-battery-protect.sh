# battery/charge-protection 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/battery-protect.sh)。
heraldctl_help_battery_protect() {
  cat <<'EOT'
  battery protect status        长期插电保护现在的状态
  battery protect on [min max]  电量保持在 min~max 之间(默认 75 80,要 20<=min<max<=100)
  battery protect off           关闭
EOT
}
