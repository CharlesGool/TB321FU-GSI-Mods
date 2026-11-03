# battery/node-access 的 heraldctl 插件(装在 /system/etc/heraldctl.d/battery.sh,由 heraldctl source)。用到 heraldctl 的 send、die。
# 子命令都由 broker 端分发,这里只转发。各 battery/* 模块在自己的 heraldctl 插件里只定义 heraldctl_help_battery_<名字>(),
# 帮助由下面的 heraldctl_help_battery 按固定顺序调用(装了哪个就显示哪个;heraldctl.d 里的文件按名字顺序加载,所以不靠各模块自己往 HERALDCTL_HELP 里追加)。
heraldctl_help_battery() {
  echo "电池"
  for _hn in health protect limit bypass; do
    type "heraldctl_help_battery_$_hn" >/dev/null 2>&1 && "heraldctl_help_battery_$_hn"
  done
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_battery"

heraldctl_cmd_battery() {
  [ -n "$1" ] || die "用法: heraldctl battery <子命令> …(看 heraldctl help 的"电池"一节)"
  send "battery $*"
}
