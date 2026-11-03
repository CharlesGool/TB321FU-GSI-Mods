# battery/bypass-charging 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/battery-bypass.sh)。
heraldctl_help_battery_bypass() {
  cat <<'EOT'
  battery bypass status         旁路充电的状态、充电器在不在、几个节点当前值
  battery bypass on             接着充电器时电池不再充电,整机用充电器供电(要几秒验证;电量<=15% 拒绝/自动关)
  battery bypass off            恢复正常充电
EOT
}
