# battery/node-access 的 broker 插件(装在 /system/etc/herald_payload/plugins/battery-lib.sh,由 herald-start.sh source)。
# 电池相关命令的公共部分:节点路径、读写、配置记忆、`battery` 命令分发、空闲时重新套用。
# 其他 battery/* 模块各自定义 heraldp_bat_sub_<子命令>(),这里的 heraldp_cmd_battery 按子命令名找过去。
# 用到 herald-start.sh 的 blog、$STATE、HERALDP_IDLE。
#
# 节点名和取值含义来自原厂 vendor.lenovo.hardware.battery-service(Battery.cpp)和原厂 services.jar 里的
# ZuiBatteryManagerService 反编译;真机读回值还没核对,README 里标了哪些是推断。
BAT_SYS=${HERALD_BAT_SYSROOT:-/sys}      # 测试时可以换成假的 sys 树
BAT_PS=$BAT_SYS/class/power_supply
BAT_FG=$BAT_SYS/class/qcom-battery
BAT_CONF=$STATE/battery.conf          # 用户设过的值(重启后重新套用),一行一个 键=值
herald_bat_node() {                      # 逻辑名 -> 节点路径
  case "$1" in
    protection)  echo "$BAT_PS/battery/protection_setting" ;;
    limit)       echo "$BAT_PS/battery/protection_setting_eu" ;;
    recharge)    echo "$BAT_PS/battery/recharge_setting" ;;
    bypass)      echo "$BAT_PS/battery/bypass_setting" ;;
    chg_enable)  echo "$BAT_PS/battery/charging_enable" ;;
    input_susp)  echo "$BAT_PS/usb/input_suspend" ;;
    *) return 1 ;;
  esac
}
herald_bat_read() {                      # 读一个节点,去掉换行回车(保留中间的空格,状态是 "Not charging" 这种);读不了返回 1 且不输出
  [ -r "$1" ] || return 1
  _bv=$(cat "$1" 2>/dev/null) || return 1
  printf '%s' "$_bv" | tr -d '\r\n'
}
herald_bat_write() {                     # 写节点并读回:写不进去返回 1;读回和写入不同返回 2(值照实输出到 $BAT_RB)
  [ -e "$1" ] || { BAT_RB=; return 1; }
  printf '%s' "$2" > "$1" 2>/dev/null || { BAT_RB=; return 1; }
  BAT_RB=$(herald_bat_read "$1")
  [ "$BAT_RB" = "$2" ] || return 2
  return 0
}
herald_bat_int() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; }   # 非空纯数字

# 配置记忆
herald_bat_cget() { [ -f "$BAT_CONF" ] && sed -n "s/^$1=//p" "$BAT_CONF" | tail -1; }
herald_bat_cset() {                      # $1 键 $2 值;值为空 = 删掉这个键
  { [ -f "$BAT_CONF" ] && grep -v "^$1=" "$BAT_CONF"; [ -n "$2" ] && echo "$1=$2"; } > "$BAT_CONF.new" 2>/dev/null
  mv -f "$BAT_CONF.new" "$BAT_CONF" 2>/dev/null
}

# `battery <子命令> [参数…]`:找 heraldp_bat_sub_<子命令>
heraldp_cmd_battery() {
  set -- $1
  _sub=$1; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err battery 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_bat_sub_$_sub" >/dev/null 2>&1; then "heraldp_bat_sub_$_sub" "$@"
  else echo "err battery 没有子命令 $_sub(装了哪些电池模块看 heraldctl help)"; fi
}

# 空闲时(主循环空闲每 5 秒调一次):
#   慢档(开机后一次,之后约每 5 分钟):核对"记住的设置"还在不在,被系统或内核改回去了就再写一遍;
#   快档(每次):需要及时反应的,比如旁路充电遇到低电量要自动关掉。
#   各模块定义 heraldp_bat_reapply_<名字>(),并把名字追加进 BAT_SLOW_MODS(慢档)或 BAT_FAST_MODS(快档)。
#   plugins/*.sh 按文件名顺序 source,各模块的文件可能排在本文件前面,所以这里不给两个列表赋初值,模块也只做变量追加。
BAT_IDLE_N=0
heraldp_bat_idle() {
  for _m in $BAT_FAST_MODS; do type "heraldp_bat_reapply_$_m" >/dev/null 2>&1 && "heraldp_bat_reapply_$_m"; done
  if [ "$BAT_IDLE_N" -eq 0 ] || [ "$BAT_IDLE_N" -ge 60 ]; then
    BAT_IDLE_N=0
    for _m in $BAT_SLOW_MODS; do type "heraldp_bat_reapply_$_m" >/dev/null 2>&1 && "heraldp_bat_reapply_$_m"; done
  fi
  BAT_IDLE_N=$((BAT_IDLE_N + 1))
}
HERALDP_IDLE="${HERALDP_IDLE:-} heraldp_bat_idle"
