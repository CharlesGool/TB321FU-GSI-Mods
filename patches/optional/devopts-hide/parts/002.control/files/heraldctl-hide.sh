# devopts-hide/control 的 heraldctl 插件(装在 /system/etc/heraldctl.d/hide.sh)。用到 heraldctl 的 send、die。
heraldctl_help_hide() {
  cat <<'EOT'
按 App 隐藏(需要装了 devopts-hide/hook;改完重启生效)
  hide [status]                           各项概况
  hide devopts [status]                   开发者选项 / ADB 隐藏的状态
  hide devopts on | off                   开 / 关
  hide devopts mode list|all              list = 只对名单里的 App 隐藏(默认);all = 对名单(白名单)和系统应用以外的所有 App 隐藏
  hide devopts add|remove <包名>          名单增减(进程名或包名)
  hide devopts list                       看名单
  hide devopts reset                      关闭并清空
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_hide"

heraldctl_cmd_hide() {
  send "hide $*"
}
