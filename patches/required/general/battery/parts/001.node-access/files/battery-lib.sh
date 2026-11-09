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
BAT_CR=$(printf '\r')
# 输出不带换行:真机的 mksh 用内建 print(printf 在 mksh 里是外部命令,要 fork);测试用的 dash / busybox 用 printf
if type print >/dev/null 2>&1; then herald_bat_out() { print -nr -- "$1"; }; else herald_bat_out() { printf '%s' "$1"; }; fi
herald_bat_read() {                      # 读一个节点的第一行,去掉回车(保留中间的空格,状态是 "Not charging" 这种);读不了返回 1 且不输出
  # V1.2:用 shell 内建的 read / print,不再每个节点 fork cat + printf + tr(battery info 一次读 30 多个节点,原来要 4.8 秒)
  [ -r "$1" ] || return 1
  _bv=
  { IFS= read -r _bv || [ -n "$_bv" ]; } < "$1" 2>/dev/null || return 1
  _bv=${_bv%"$BAT_CR"}
  herald_bat_out "$_bv"
}
# 开机后不变的值(电芯出厂/激活日期、厂商代码、设计容量):每个进程第一次读真节点,之后用内存里的值。
#   电量计的日期节点走 I2C,一个 150 ms;$1 = 缓存名(字母数字下划线),$2 = 节点。
#   结果放在 $_bsv,不输出:必须在当前 shell 里调用(不能 $(...)),否则缓存写进子 shell 就丢了。
herald_bat_static() {
  _bsv=
  case "$1" in ""|*[!A-Za-z0-9_]*) return 1 ;; esac
  eval "_bsv=\${BATS_$1-__none__}"
  if [ "$_bsv" = __none__ ]; then
    _bsv=$(herald_bat_read "$2")
    eval "BATS_$1=\$_bsv"
  fi
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

# `battery overview`:一次给出 info + 三个 status(电池管理 App 用,一次请求代替四次)。
#   每段以 "--- <名字>" 开头,段内就是对应命令的原样回包。
heraldp_bat_sub_overview() {
  echo "ok battery overview"
  for _os in info protect limit bypass; do
    type "heraldp_bat_sub_$_os" >/dev/null 2>&1 || continue
    echo "--- $_os"
    if [ "$_os" = info ]; then "heraldp_bat_sub_$_os"; else "heraldp_bat_sub_$_os" status; fi
  done
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
