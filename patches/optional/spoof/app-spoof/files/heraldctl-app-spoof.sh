# spoof/app-spoof 的 heraldctl 插件(装在 /system/etc/heraldctl.d/app-spoof.sh)。用到 heraldctl 的 send、die。
# 合并 pending/heraldctl.diff 之后也可以写成 heraldctl spoof mode … / heraldctl spoof apps …,两种写法等价。
heraldctl_help_app_spoof() {
  cat <<'EOT'
伪装模式(按 App / 全局)
  spoofmode                     当前模式和这次开机实际生效的方式
  spoofmode app|global          切换(重启生效);app = 只给名单里的 App 换 Build.*,系统属性不动
  spoofapps                     按 App 伪装的名单(默认 + 额外)
  spoofapps add|remove <名字>   额外名单加/减(进程名或包名,重启生效)
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_app_spoof"

heraldctl_cmd_spoofmode() {
  case "$1" in ""|app|global) ;; *) die "用法: heraldctl spoofmode [app|global]" ;; esac
  send "spoof_mode $*"
}
heraldctl_cmd_spoofapps() {
  case "$1" in ""|list) send "spoof_apps list" ;;
    add|remove) [ -n "$2" ] || die "用法: heraldctl spoofapps add|remove <进程名或包名>"; send "spoof_apps $1 $2" ;;
    *) die "用法: heraldctl spoofapps [list] | add|remove <进程名或包名>" ;;
  esac
}
