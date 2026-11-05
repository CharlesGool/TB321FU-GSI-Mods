# navbar-hide 的 heraldctl 插件(装在 /system/etc/heraldctl.d/navbar.sh,由 heraldctl source)。用到 heraldctl 的 send、die。
heraldctl_help_navbar() {
  cat <<'EOF'
导航栏
  navbar hide                   隐藏底部提示线/小白条, App 用满全屏, 手势照旧(平板任务栏和手机导航栏两种都管)
  navbar show                   恢复
  navbar status                 当前状态、导航模式、底部是任务栏还是导航栏
  只在手势导航下生效; 三键导航时自动恢复, 切回手势自动再隐藏。设置重启后保留。
EOF
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_navbar"

heraldctl_cmd_navbar() {
  case "$1" in
    hide|show|status) send "navbar $1" ;;
    *) die "navbar 子命令: hide show status" ;;
  esac
}
