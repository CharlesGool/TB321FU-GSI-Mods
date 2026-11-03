# refresh-rate/control 的 heraldctl 插件(装在 /system/etc/heraldctl.d/refresh-rate.sh)。用到 heraldctl 的 send、die。
# 子命令都由 broker 端分发,这里只转发。帮助:自己的几行 + refresh-rate/adaptive 的几行(装了才有,它定义 heraldctl_help_refresh_adaptive)。
heraldctl_help_refresh() {
  cat <<'EOT'
刷新率
  refresh status                当前实际刷新率、min/peak 设置、面板支持的档位
  refresh modes                 面板支持的档位
  refresh set <Hz>              锁定到某一档(例 refresh set 60)
  refresh range <最小> <最大>    限定范围,系统在范围内自动挑(0 = 不限,例 refresh range 60 120)
  refresh auto                  恢复系统默认
EOT
  type heraldctl_help_refresh_adaptive >/dev/null 2>&1 && heraldctl_help_refresh_adaptive
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_refresh"

heraldctl_cmd_refresh() {
  [ -n "$1" ] || die "用法: heraldctl refresh <子命令> …(看 heraldctl help 的"刷新率"一节)"
  send "refresh $*"
}
