# rooted-shell 的 heraldctl 插件(装在 /system/etc/heraldctl.d/rooted-shell.sh,由 heraldctl source)。用到 heraldctl 的 send、die。
heraldctl_help_rsh() {
  cat <<'HELP'
root shell(调试用;默认关)
  rsh on [分钟]            打开(默认 15 分钟,最多 60),到点自动关
  rsh off | rsh status
  rsh <命令>               以 root 经 sh -c 跑整条命令,输出原样打印,退出码同命令;支持管道、重定向
    电脑上带管道要整条用引号包住:adb shell "heraldctl rsh 'ls -l /data/misc | head'"
    (Windows cmd 外层用双引号、里层单引号)
    单条 60 秒超时,输出最多 256KB;每条命令都记进 heraldctl log;只接受命令行,不给前端 App
HELP
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_rsh"

heraldctl_cmd_rsh() {
  [ $# -ge 1 ] || die "用法: heraldctl rsh on [分钟] | off | status | <命令>"
  case "$1" in
    on|off|status) send "rsh $*"; return $? ;;
  esac
  rf=$TMPF.rs
  send "rsh $*" > "$rf"; src=$?
  first=$(head -1 "$rf")
  case "$first" in
    "ok rsh rc="*)
      tail -n +2 "$rf"; rm -f "$rf"
      rc=${first#ok rsh rc=}; case "$rc" in ""|*[!0-9]*) rc=1 ;; esac
      return "$rc" ;;
    *) cat "$rf"; rm -f "$rf"; return "$src" ;;
  esac
}
