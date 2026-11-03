# perf/node-access 的 heraldctl 插件(装在 /system/etc/heraldctl.d/perf.sh)。用到 heraldctl 的 send、die。
# 帮助 = 这里的标题 + 各性能模块定义的 heraldctl_help_perf_<名字>。
heraldctl_help_perf() {
  echo "性能调节(只调 CPU/GPU 的频率上下限,不绕过温控)"
  for _h in cpu gpu profiles temps game; do type "heraldctl_help_perf_$_h" >/dev/null 2>&1 && "heraldctl_help_perf_$_h"; done
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_perf"

heraldctl_cmd_perf() {
  [ -n "$1" ] || die "用法: heraldctl perf <子命令> …(看 heraldctl help 的"性能调节"一节)"
  send "perf $*"
}
