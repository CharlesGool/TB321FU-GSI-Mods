#!/usr/bin/env bash
# 电池插件(patches/required/general/battery/*)的单元测试:假的 sysfs 树 + 桩函数,在 dash 和 busybox sh 下各跑一遍。
# 用法: toolkit/test-battery-plugins.sh      (不碰真机,不需要 root)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
B=$REPO/patches/required/general/battery/parts
T=$(mktemp -d "${TMPDIR:-/tmp}/battest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { # chk <说明> <输出> <应包含的行(整行匹配)>
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nochk(){ if printf '%s\n' "$2" | grep -qxF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }

mkfake() {   # mkfake <目录> : 造一棵假的 sys 树
  local S=$1; rm -rf "$S"; mkdir -p "$S/class/power_supply/battery" "$S/class/power_supply/usb" "$S/class/power_supply/wireless" "$S/class/qcom-battery"
  local P=$S/class/power_supply
  echo 61 > $P/battery/capacity; echo Charging > $P/battery/status; echo Good > $P/battery/health
  echo 317 > $P/battery/temp; echo 4200000 > $P/battery/voltage_now; echo -1500000 > $P/battery/current_now
  echo 95100 > $P/battery/protection_setting; echo 195100 > $P/battery/protection_setting_eu
  echo 95 > $P/battery/recharge_setting; echo 0 > $P/battery/bypass_setting; echo 1 > $P/battery/charging_enable
  echo 0 > $P/usb/input_suspend; echo 1 > $P/usb/online; echo 0 > $P/wireless/online
  echo 123 > $S/class/qcom-battery/fg1_cycle_count; echo 98 > $S/class/qcom-battery/fg1_soh; echo 305 > $S/class/qcom-battery/fg1_temp
  echo 456 > $S/class/qcom-battery/fg2_cycle_count; echo 97 > $S/class/qcom-battery/fg2_soh
  echo ATL > $S/class/qcom-battery/battery1_manufacturer; echo SCUD > $S/class/qcom-battery/battery2_manufacturer
}

run() {   # run <sh> <sysroot> <状态目录> <命令…> : 在指定 shell 里加载全部 battery 插件,执行一串命令,输出结果
  local sh=$1 S=$2 ST=$3; shift 3
  cat > "$T/drv.sh" <<DRV
STATE=$ST; mkdir -p "\$STATE"
HERALD_BAT_SYSROOT=$S; HERALD_BAT_SLEEP=0; HERALDP_IDLE=""
blog() { echo "\$*" >> "$T/blog.txt"; }
# 假内核:sleep 时按 charging_enable 的值(和极性)更新电池状态
sleep() {
  [ -n "\${FAKE_POL:-}" ] || return 0
  _v=\$(cat $S/class/power_supply/battery/charging_enable)
  [ "\$FAKE_POL" = never ] && return 0
  if [ "\$_v" = "\$FAKE_POL" ]; then echo "Not charging" > $S/class/power_supply/battery/status; else echo Charging > $S/class/power_supply/battery/status; fi
}
for f in $B/005.bypass-charging/files/battery-bypass.sh $B/002.health-report/files/battery-health.sh $B/001.node-access/files/battery-lib.sh $B/004.charge-limit/files/battery-limit.sh $B/003.charge-protection/files/battery-protect.sh; do . "\$f"; done
DRV
  printf '%s\n' "$@" >> "$T/drv.sh"
  $sh "$T/drv.sh" 2>&1
}

for SH in dash "busybox sh"; do
  command -v ${SH%% *} >/dev/null || { echo "跳过 $SH(没装)"; continue; }
  echo "== $SH"
  S=$T/sys; ST=$T/state; rm -rf "$ST"; mkfake "$S"
  # --- info
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "info"'); chk info "$o" "ok battery info"
  chk info "$o" "level=61"; chk info "$o" "temp_c=31.7"; chk info "$o" "voltage_mv=4200"; chk info "$o" "current_ma=-1500"
  chk info "$o" "cell1_cycle_count_raw=123"; chk info "$o" "cell2_soh_raw=97"; chk info "$o" "cells=2"; chk info "$o" "cycle_max=456"
  chk info "$o" "cell2_manufacturer=SCUD"; chk info "$o" "node_protection=95100"; chk info "$o" "node_limit=195100"
  rm -f "$S/class/power_supply/battery/temp" "$S/class/qcom-battery/fg2_soh"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "info"'); nochk info-missing "$o" "temp_c=31.7"; nochk info-missing "$o" "cell2_soh_raw=97"
  # --- protect
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "protect on 75 80"'); chk protect-on "$o" "ok battery protect on min=75 max=80 raw=175080 readback=175080"
  [ "$(cat $S/class/power_supply/battery/protection_setting)" = 175080 ] && ok || bad "protect 节点值"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "protect status"'); chk protect-st "$o" "protect=on"; chk protect-st "$o" "min=75"; chk protect-st "$o" "max=80"; chk protect-st "$o" "remembered=on:75:80"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "protect on 80 70"'); chk protect-bad "$o" "err battery_protect 要 20 <= min < max <= 100"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "protect on a b"'); chk protect-bad2 "$o" "err battery_protect 用法: battery protect on [min max],min/max 是百分数"
  echo 95100 > $S/class/power_supply/battery/protection_setting      # 系统改回去
  run "$SH" "$S" "$ST" 'BAT_IDLE_N=0; heraldp_bat_idle' >/dev/null
  [ "$(cat $S/class/power_supply/battery/protection_setting)" = 175080 ] && ok || bad "protect 没有被重新套用"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "protect off"'); chk protect-off "$o" "ok battery protect off raw=95100 readback=95100"
  [ -z "$(cat $ST/battery.conf 2>/dev/null)" ] && ok || bad "protect off 后配置没清"
  # --- limit
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit 80"'); chk limit-80 "$o" "ok battery limit on limit=80 recharge=95 raw=176080 readback=176080 recharge_write=0"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit status"'); chk limit-st "$o" "floor=76"; chk limit-st "$o" "limit=80"; chk limit-st "$o" "remembered=80:95"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit 100"'); chk limit-100 "$o" "ok battery limit off limit=100 recharge=95 raw=195100 readback=195100 recharge_write=0"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit 85 90"'); chk limit-85 "$o" "ok battery limit on limit=85 recharge=90 raw=176085 readback=176085 recharge_write=0"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit 10"'); chk limit-bad "$o" "err battery_limit 要 20 <= 上限 <= 100,50 <= 回充比例 <= 100"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit off"'); chk limit-off "$o" "ok battery limit off limit=100 recharge=95 raw=195100 readback=195100 recharge_write=0"
  rm -f "$S/class/power_supply/battery/protection_setting_eu"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "limit 80"'); chk limit-nonode "$o" "err battery_limit 写不进 $S/class/power_supply/battery/protection_setting_eu"
  # --- bypass:极性 A(写 1 = 关充电,和 HAL 一致)
  mkfake "$S"; rm -rf "$ST"
  o=$(FAKE_POL=1 run "$SH" "$S" "$ST" 'FAKE_POL=1' 'heraldp_cmd_battery "bypass on"'); chk bypass-A "$o" "ok battery bypass on verified=yes chg_off=1"
  [ "$(cat $S/class/power_supply/battery/charging_enable)" = 1 ] && ok || bad "bypass A 节点值"
  o=$(run "$SH" "$S" "$ST" 'FAKE_POL=1' 'heraldp_cmd_battery "bypass off"'); chk bypass-off "$o" "ok battery bypass off"
  [ "$(cat $S/class/power_supply/battery/charging_enable)" = 0 ] && ok || bad "bypass off 应写 0(1 - chg_off)"
  # 极性 B(0 = 关充电):先试 1 仍在充 → 换 0 → 记住
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'FAKE_POL=0' 'heraldp_cmd_battery "bypass on"'); chk bypass-B "$o" "ok battery bypass on verified=yes chg_off=0"
  chk bypass-B-conf "$(cat $ST/battery.conf)" "chg_off=0"
  # 两个值都没用:回滚
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'FAKE_POL=never' 'heraldp_cmd_battery "bypass on"'); chk bypass-never "$o" "err battery_bypass 没生效(电池状态=on),已恢复原值 charging_enable=1"
  [ "$(cat $S/class/power_supply/battery/charging_enable)" = 1 ] && ok || bad "回滚后 charging_enable 应是原值 1"
  [ ! -f "$ST/battery.conf" ] || ! grep -q '^bypass=' "$ST/battery.conf" && ok || bad "失败后不该记住 bypass=on"
  # 输入被挂起 → 状态 Discharging → 回滚
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'sleep() { echo Discharging > '"$S"'/class/power_supply/battery/status; }' 'heraldp_cmd_battery "bypass on"'); chk bypass-discharging "$o" "err battery_bypass 没生效(电池状态=discharging),已恢复原值 charging_enable=1"
  # 没接充电器
  mkfake "$S"; rm -rf "$ST"; echo 0 > $S/class/power_supply/usb/online
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "bypass on"'); chk bypass-nochg "$o" "ok battery bypass on charger=none note=没接充电器,无法验证效果;接上后由守护复查 chg_off=1"
  # 低电量拒绝 / 自动关
  mkfake "$S"; rm -rf "$ST"; echo 12 > $S/class/power_supply/battery/capacity
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "bypass on"'); chk bypass-low "$o" "err battery_bypass 电量 12% <= 15%,先充一会儿"
  mkfake "$S"; rm -rf "$ST"
  run "$SH" "$S" "$ST" 'FAKE_POL=1' 'heraldp_cmd_battery "bypass on"' >/dev/null
  echo 10 > $S/class/power_supply/battery/capacity
  run "$SH" "$S" "$ST" 'heraldp_bat_idle' >/dev/null
  [ "$(cat $S/class/power_supply/battery/charging_enable)" = 0 ] && ok || bad "低电量没有自动恢复充电"
  grep -q '^bypass=' "$ST/battery.conf" 2>/dev/null && bad "低电量后还记着 bypass=on" || ok
  # 系统把 charging_enable 改回去 → 快档重写
  mkfake "$S"; rm -rf "$ST"
  run "$SH" "$S" "$ST" 'FAKE_POL=1' 'heraldp_cmd_battery "bypass on"' >/dev/null
  echo 0 > $S/class/power_supply/battery/charging_enable
  run "$SH" "$S" "$ST" 'heraldp_bat_idle' >/dev/null
  [ "$(cat $S/class/power_supply/battery/charging_enable)" = 1 ] && ok || bad "bypass 没有被重新套用"
  # 分发
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "nope"'); chk dispatch "$o" "err battery 没有子命令 nope(装了哪些电池模块看 heraldctl help)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_battery "Bad;x"'); chk dispatch2 "$o" "err battery 子命令只能是小写字母数字"
done
echo "通过 $pass 项, 失败 $fail 项"
[ "$fail" = 0 ]
