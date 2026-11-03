# battery/health-report 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/battery-health.sh)。子命令由 node-access 里的 heraldctl battery 转发;帮助由 node-access 的 heraldctl_help_battery 按固定顺序调用本函数。
heraldctl_help_battery_health() {
  cat <<'EOT'
  battery info                  电量/温度/电压电流,两颗电芯各自的循环次数、健康度、日期、厂商(原始值),几个电池节点的当前值
EOT
}
