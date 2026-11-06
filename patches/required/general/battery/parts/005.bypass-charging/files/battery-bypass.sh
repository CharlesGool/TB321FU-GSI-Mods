# battery/bypass-charging 的 broker 插件(装在 /system/etc/herald_payload/plugins/battery-bypass.sh)。
# 旁路充电:接着充电器时电池不再充电,整机用充电器供电(玩游戏时不让电池发热、不损耗)。
#   原厂做法(ZuiBatteryManagerService.setBypassChargingStatus,游戏助手用):两条"投票"——
#     input_suspend 不挂起(输入保持打开)+ 电池充电关闭。落到原厂 HAL:setUsbSupplyDisabled(false) 写 usb/input_suspend=0,
#     setBatteryChargeDisabled(true) 写 battery/charging_enable=<布尔原值,即 1>。
#   HAL 没做取反,而节点叫 charging_enable,所以"1 = 关充电"还是"1 = 开充电"在没上真机前不能确定。这里的做法:
#     先按 HAL 的写法试,等几秒看 battery/status;还是 Charging 就换另一个值再试一次;两个都不行就恢复原值并报错。
#     试出来的值记在 battery.conf 的 chg_off,以后直接用。
#   安全:电量 <= BAT_BYPASS_MIN% 时自动关掉旁路并去掉记忆;状态变成 Discharging 同时充电器在位(= 输入被挂起,整机在吃电池)就回滚。
#   battery bypass status | on | off
BAT_BYPASS_MIN=15
BAT_BYPASS_WAIT=${HERALD_BAT_SLEEP:-4}
herald_bat_charger() {      # 有外部电源 0 / 没有 1
  [ "$(herald_bat_read "$BAT_PS/usb/online")" = 1 ] && return 0
  [ "$(herald_bat_read "$BAT_PS/wireless/online")" = 1 ] && return 0
  return 1
}
herald_bat_chgoff_val() { _v=$(herald_bat_cget chg_off); case "$_v" in 0|1) echo "$_v" ;; *) echo 1 ;; esac; }
# 现在电池是不是被关了充电:Not charging = 是;Charging = 否;其余(Full 等)= 看不出来
herald_bat_charge_state() {
  case "$(herald_bat_read "$BAT_PS/battery/status")" in
    "Not charging") echo off ;; Charging) echo on ;; Discharging) echo discharging ;; *) echo unknown ;;
  esac
}
herald_bat_bypass_on() {    # 成功输出 说明 并返回 0
  _ce=$(herald_bat_node chg_enable); _is=$(herald_bat_node input_susp)
  [ -e "$_ce" ] || { echo "err battery_bypass 没有 $_ce(这台机器没有这个节点)"; return 1; }
  _orig=$(herald_bat_read "$_ce")
  [ -e "$_is" ] && herald_bat_write "$_is" 0
  _off=$(herald_bat_chgoff_val)
  herald_bat_write "$_ce" "$_off"
  if ! herald_bat_charger; then echo "ok battery bypass on charger=none note=没接充电器,无法验证效果;接上后由守护复查 chg_off=$_off"; return 0; fi
  sleep "$BAT_BYPASS_WAIT"
  _st=$(herald_bat_charge_state)
  if [ "$_st" = on ]; then       # 还在充:换另一个值
    _alt=$((1 - _off)); herald_bat_write "$_ce" "$_alt"; sleep "$BAT_BYPASS_WAIT"; _st=$(herald_bat_charge_state)
    [ "$_st" = off ] && { herald_bat_cset chg_off "$_alt"; _off=$_alt; blog "battery: bypass 试出 charging_enable 的关充电值 = $_alt"; }
  fi
  case "$_st" in
    off) echo "ok battery bypass on verified=yes chg_off=$_off" ;;
    unknown) echo "ok battery bypass on verified=no note=电池状态是 $(herald_bat_read "$BAT_PS/battery/status"),看不出充没充(电量满时正常);chg_off=$_off" ;;
    *)  # on(两个值都没用)或 discharging(输入被挂起了):回滚
      [ -n "$_orig" ] && herald_bat_write "$_ce" "$_orig"
      [ -e "$_is" ] && herald_bat_write "$_is" 0
      echo "err battery_bypass 没生效(电池状态=$_st),已恢复原值 charging_enable=$_orig"; return 1 ;;
  esac
  return 0
}
herald_bat_bypass_off() {
  _ce=$(herald_bat_node chg_enable); _is=$(herald_bat_node input_susp); _off=$(herald_bat_chgoff_val)
  herald_bat_write "$_ce" "$((1 - _off))"
  [ -e "$_is" ] && herald_bat_write "$_is" 0
}
heraldp_bat_sub_bypass() {
  case "$1" in
    status|"")
      echo "ok battery bypass"
      echo "bypass=$(herald_bat_cget bypass | sed 's/^$/off/')"
      echo "charger=$(herald_bat_charger && echo yes || echo no)"
      echo "battery_status=$(herald_bat_read "$BAT_PS/battery/status")"
      echo "level=$(herald_bat_read "$BAT_PS/battery/capacity")"
      echo "node_chg_enable=$(herald_bat_read "$(herald_bat_node chg_enable)")"
      echo "node_input_suspend=$(herald_bat_read "$(herald_bat_node input_susp)")"
      echo "chg_off=$(herald_bat_chgoff_val)"
      echo "node_bypass_level=$(herald_bat_read "$(herald_bat_node bypass)")" ;;
    on)
      _lv=$(herald_bat_read "$BAT_PS/battery/capacity")
      herald_bat_int "$_lv" && [ "$_lv" -le "$BAT_BYPASS_MIN" ] && { echo "err battery_bypass 电量 ${_lv}% <= ${BAT_BYPASS_MIN}%,先充一会儿"; return; }
      _out=$(herald_bat_bypass_on) || { printf '%s\n' "$_out"; return; }
      herald_bat_cset bypass on; blog "battery: bypass on"; printf '%s\n' "$_out" ;;
    off)
      herald_bat_bypass_off; herald_bat_cset bypass ""; blog "battery: bypass off"
      echo "ok battery bypass off" ;;
    *) echo "err battery_bypass 用法: battery bypass status | on | off" ;;
  esac
}
# 快档:记着"开"时,电量过低就关掉;充电器重新接上、系统把节点改回去了就再写
heraldp_bat_reapply_bypass() {
  [ "$(herald_bat_cget bypass)" = on ] || return 0
  _lv=$(herald_bat_read "$BAT_PS/battery/capacity")
  if herald_bat_int "$_lv" && [ "$_lv" -le "$BAT_BYPASS_MIN" ]; then
    herald_bat_bypass_off; herald_bat_cset bypass ""; blog "battery: bypass 电量 ${_lv}% 过低,自动关闭"; return 1
  fi
  herald_bat_charger || return 0
  _ce=$(herald_bat_node chg_enable); _off=$(herald_bat_chgoff_val)
  [ "$(herald_bat_read "$_ce")" = "$_off" ] && return 0
  herald_bat_write "$_ce" "$_off"; herald_bat_write "$(herald_bat_node input_susp)" 0
  blog "battery: bypass 重新套用 charging_enable=$_off"; return 1
}
BAT_FAST_MODS="${BAT_FAST_MODS:-} bypass"
