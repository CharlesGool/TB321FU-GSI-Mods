# statusbar-netspeed/control 的 heraldctl 插件(装在 /system/etc/heraldctl.d/netspeed.sh)。用到 heraldctl 的 send、die。
heraldctl_help_netspeed() {
  cat <<'EOT'
状态栏网速显示(需要装了 statusbar-netspeed/display;改完 1 秒左右生效)
  netspeed [status]             开关和样式
  netspeed on | off             开 / 关
  netspeed pos start|end        位置:start = 时钟后面,end = 右边系统图标前面(默认)
  netspeed mode both|down|total 两行上下行(默认)/ 只下行 / 合计
  netspeed unit bytes|bits      字节制(默认)/ 比特制
  netspeed reset                恢复默认
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_netspeed"

heraldctl_cmd_netspeed() {
  send "netspeed $*"
}
