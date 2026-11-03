# statusbar-netspeed/control 的 broker 插件(装在 /system/etc/herald_payload/plugins/speed-control.sh)。
# 状态栏网速显示(statusbar-netspeed/display)的开关和样式:读写 Settings.Global 里的 herald_netspeed* 四个键,
# 状态栏那边每秒读一次,所以改完 1 秒左右就生效。用到 herald-start.sh 的 herald_sys。
#   netspeed status | on | off | pos start|end | mode both|down|total | unit bytes|bits | reset
#   键和默认值:herald_netspeed(默认开)、herald_netspeed_pos(end)、herald_netspeed_mode(both)、herald_netspeed_unit(bytes)。
#   没设的键 = 默认值;reset = 四个键全删。
herald_ns_sget() { _v=$(herald_sys /system/bin/settings get global "$1" | tr -d '\r\n'); [ "$_v" = null ] && _v=; echo "$_v"; }
herald_ns_sput() { herald_sys /system/bin/settings put global "$1" "$2" >/dev/null 2>&1; [ "$(herald_ns_sget "$1")" = "$2" ]; }
herald_ns_sdel() { herald_sys /system/bin/settings delete global "$1" >/dev/null 2>&1; [ -z "$(herald_ns_sget "$1")" ]; }

heraldp_netspeed_sub_status() {
  _e=$(herald_ns_sget herald_netspeed); _p=$(herald_ns_sget herald_netspeed_pos); _m=$(herald_ns_sget herald_netspeed_mode); _u=$(herald_ns_sget herald_netspeed_unit)
  echo "ok 状态栏网速"
  [ "$_e" = 0 ] && echo "enabled=0" || echo "enabled=1"
  [ "$_p" = start ] && echo "pos=start" || echo "pos=end"
  case "$_m" in down|total) echo "mode=$_m" ;; *) echo "mode=both" ;; esac
  [ "$_u" = bits ] && echo "unit=bits" || echo "unit=bytes"
}
heraldp_netspeed_sub_on()  { if herald_ns_sput herald_netspeed 1; then echo "ok 已开启(1 秒左右生效)"; else echo "err 写 herald_netspeed 失败"; fi; }
heraldp_netspeed_sub_off() { if herald_ns_sput herald_netspeed 0; then echo "ok 已关闭"; else echo "err 写 herald_netspeed 失败"; fi; }
heraldp_netspeed_sub_pos() {
  case "${1:-}" in start|end) ;; *) echo "err 用法: netspeed pos start|end"; return ;; esac
  if herald_ns_sput herald_netspeed_pos "$1"; then echo "ok 位置 $1"; else echo "err 写 herald_netspeed_pos 失败"; fi
}
heraldp_netspeed_sub_mode() {
  case "${1:-}" in both|down|total) ;; *) echo "err 用法: netspeed mode both|down|total"; return ;; esac
  if herald_ns_sput herald_netspeed_mode "$1"; then echo "ok 模式 $1"; else echo "err 写 herald_netspeed_mode 失败"; fi
}
heraldp_netspeed_sub_unit() {
  case "${1:-}" in bytes|bits) ;; *) echo "err 用法: netspeed unit bytes|bits"; return ;; esac
  if herald_ns_sput herald_netspeed_unit "$1"; then echo "ok 单位 $1"; else echo "err 写 herald_netspeed_unit 失败"; fi
}
heraldp_netspeed_sub_reset() {
  _bad=""
  for _k in herald_netspeed herald_netspeed_pos herald_netspeed_mode herald_netspeed_unit; do herald_ns_sdel "$_k" || _bad="$_bad $_k"; done
  if [ -z "$_bad" ]; then echo "ok 已恢复默认(开、右侧、两行、字节制)"; else echo "err 这些键没删掉:$_bad"; fi
}

heraldp_cmd_netspeed() {
  set -f; set -- $1; set +f
  _sub=${1:-status}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err netspeed 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_netspeed_sub_$_sub" >/dev/null 2>&1; then "heraldp_netspeed_sub_$_sub" "${1:-}"
  else echo "err netspeed 没有子命令 $_sub"; fi
}
