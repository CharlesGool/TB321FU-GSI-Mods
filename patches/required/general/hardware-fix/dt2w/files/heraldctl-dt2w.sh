# dt2w 的 heraldctl 插件(装在 /system/etc/heraldctl.d/dt2w.sh,由 heraldctl source)。用到 heraldctl 的 send、die。
heraldctl_help_dt2w() {
  cat <<'EOF'
双击唤醒
  dt2w on | off                 打开/关闭(等同 设置 → 显示 → 点按唤醒)
  dt2w status                   设置值、/proc/gesture_control 当前值、点按唤醒开关是否可见
EOF
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_dt2w"

heraldctl_cmd_dt2w() {
  case "$1" in
    on|off|status|"") send "dt2w ${1:-status}" ;;
    *) die "dt2w 子命令: on off status" ;;
  esac
}
