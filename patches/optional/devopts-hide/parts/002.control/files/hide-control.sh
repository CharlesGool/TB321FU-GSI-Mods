# devopts-hide/control 的 broker 插件(装在 /system/etc/herald_payload/plugins/hide-control.sh,由 herald-start.sh source)。
# 按 App 隐藏的规则管理:现在只有 devopts(开发者选项 / ADB 状态,配合 devopts-hide/hook 的 framework 钩子)。
# 规则存在 $STATE 下,每次改完调 herald-devopts-hide.sh 重写 zygote 读的配置文件;zygote 只在开机时读一次,所以都要重启生效。用到 blog、$STATE。
#   hide [status]                                      各项概况
#   hide devopts [status] | on | off | list | reset
#   hide devopts mode list|all                         list = 只对名单里的 App 隐藏(默认);all = 对名单(白名单)和系统应用以外的所有 App 隐藏
#   hide devopts add|remove <进程名或包名>
# 数据:devhide.conf(enabled=0|1、mode=list|all)、devhide.names(名单,一行一个)。devhide.boot 是开机时那份配置的副本,用来判断要不要重启。
DH_STATE=${HERALD_DH_STATE:-$STATE}
DH_CONF=$DH_STATE/devhide.conf
DH_NAMES=$DH_STATE/devhide.names
DH_BOOT=$DH_STATE/devhide.boot
DH_FILE=${HERALD_DH_CONF:-/data/system/settings_compat.conf}
DH_APPLY=${HERALD_DH_APPLY:-"/system/bin/sh /system/etc/herald_payload/herald-devopts-hide.sh"}
DH_MAX=${HERALD_DH_MAX:-500}
DH_KEYS="development_settings_enabled adb_enabled adb_wifi_enabled wait_for_debugger mock_location"

herald_dh_cget() { [ -f "$DH_CONF" ] && sed -n "s/^$1=//p" "$DH_CONF" | tail -1; return 0; }
herald_dh_cset() {                                       # $1 键 $2 值;值为空 = 删掉
  { [ -f "$DH_CONF" ] && grep -v "^$1=" "$DH_CONF"; [ -n "$2" ] && echo "$1=$2"; } > "$DH_CONF.new" 2>/dev/null
  mv -f "$DH_CONF.new" "$DH_CONF" 2>/dev/null
  return 0
}
herald_dh_mode() { case "$(herald_dh_cget mode)" in all) echo all ;; *) echo list ;; esac; }
herald_dh_on() { [ "$(herald_dh_cget enabled)" = 1 ]; }
herald_dh_count() { if [ -f "$DH_NAMES" ]; then grep -c . "$DH_NAMES"; else echo 0; fi; }
herald_dh_nameok() { case "$1" in ""|*[!A-Za-z0-9._:]*|.*|*..*) return 1 ;; esac; return 0; }
herald_dh_apply() { $DH_APPLY >/dev/null 2>&1; }
herald_dh_reboot() {                                     # 现在的配置文件和开机时那份不一样 = 要重启
  if [ -f "$DH_FILE" ] && [ -f "$DH_BOOT" ]; then cmp -s "$DH_FILE" "$DH_BOOT" && echo 0 || echo 1
  elif [ ! -f "$DH_FILE" ] && [ ! -f "$DH_BOOT" ]; then echo 0
  else echo 1; fi
}

heraldp_hdo_sub_status() {
  echo "ok 开发者选项/ADB 隐藏"
  if herald_dh_on; then echo "enabled=1"; else echo "enabled=0"; fi
  echo "mode=$(herald_dh_mode)"
  echo "names=$(herald_dh_count)"
  if [ -f "$DH_FILE" ]; then echo "rules_file=present"; else echo "rules_file=absent"; fi
  echo "reboot_required=$(herald_dh_reboot)"
  echo "keys=$DH_KEYS"
  if ! herald_dh_on; then :
  elif [ "$(herald_dh_mode)" = list ] && [ "$(herald_dh_count)" = 0 ]; then echo "note=list 模式名单为空,不会隐藏任何 App"; fi
  return 0
}
heraldp_hdo_sub_on() {
  herald_dh_cset enabled 1; herald_dh_apply
  blog "hide devopts: on"
  if [ "$(herald_dh_mode)" = list ] && [ "$(herald_dh_count)" = 0 ]; then echo "ok devopts on(名单为空,先 add 包名才有效)"
  else echo "ok devopts on reboot-required"; fi
}
heraldp_hdo_sub_off() { herald_dh_cset enabled 0; herald_dh_apply; blog "hide devopts: off"; echo "ok devopts off reboot-required"; }
heraldp_hdo_sub_mode() {
  case "${1:-}" in list|all) ;; *) echo "err 用法: hide devopts mode list|all"; return ;; esac
  herald_dh_cset mode "$1"; herald_dh_apply; blog "hide devopts: mode $1"
  echo "ok devopts mode $1 reboot-required"
}
heraldp_hdo_sub_add() {
  herald_dh_nameok "${1:-}" || { echo "err 用法: hide devopts add <进程名或包名>"; return; }
  if [ -f "$DH_NAMES" ] && grep -qxF -- "$1" "$DH_NAMES"; then echo "ok devopts add $1(已在名单里)"; return; fi
  [ "$(herald_dh_count)" -lt "$DH_MAX" ] || { echo "err 名单已满($DH_MAX 条)"; return; }
  echo "$1" >> "$DH_NAMES" || { echo "err 写名单失败"; return; }
  herald_dh_apply; blog "hide devopts: add $1"
  echo "ok devopts add $1 reboot-required"
}
heraldp_hdo_sub_remove() {
  herald_dh_nameok "${1:-}" || { echo "err 用法: hide devopts remove <进程名或包名>"; return; }
  if [ ! -f "$DH_NAMES" ] || ! grep -qxF -- "$1" "$DH_NAMES"; then echo "ok devopts remove $1(本来就不在名单里)"; return; fi
  grep -vxF -- "$1" "$DH_NAMES" > "$DH_NAMES.new"; mv -f "$DH_NAMES.new" "$DH_NAMES"
  herald_dh_apply; blog "hide devopts: remove $1"
  echo "ok devopts remove $1 reboot-required"
}
heraldp_hdo_sub_list() {
  echo "ok devopts list mode=$(herald_dh_mode)"
  if [ -f "$DH_NAMES" ]; then while IFS= read -r _dn; do [ -n "$_dn" ] && echo "name=$_dn"; done < "$DH_NAMES"; fi
  return 0
}
heraldp_hdo_sub_reset() {
  rm -f "$DH_CONF" "$DH_NAMES"; herald_dh_apply; blog "hide devopts: reset"
  echo "ok devopts reset(关闭,list 模式,名单清空) reboot-required"
}

heraldp_hide_area_devopts() {
  _sub=${1:-status}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err hide devopts 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_hdo_sub_$_sub" >/dev/null 2>&1; then "heraldp_hdo_sub_$_sub" "${1:-}"
  else echo "err hide devopts 没有子命令 $_sub"; fi
}

heraldp_cmd_hide() {
  set -f; set -- $1; set +f
  _area=${1:-status}; [ $# -gt 0 ] && shift
  case "$_area" in
    status)
      echo "ok 隐藏"
      if herald_dh_on; then echo "devopts=on"; else echo "devopts=off"; fi ;;
    devopts) heraldp_hide_area_devopts "$@" ;;
    *) echo "err hide 没有 $_area(现有: devopts)" ;;
  esac
}
