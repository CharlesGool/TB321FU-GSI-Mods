#!/usr/bin/env bash
# devopts-hide/control 的单元测试:插件 + 写配置文件的脚本都在临时目录里跑(chcon、dmesg 都桩掉),dash 和 busybox sh 各一遍;
# 有 javac 时再用 devopts-hide 的 Java 解析器读一遍生成的配置文件。用法: toolkit/test-hide-plugin.sh  (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/patches/optional/devopts-hide/parts/002.control/files
T=$(mktemp -d "${TMPDIR:-/tmp}/hidetest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
has()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok; else bad "$1: 缺子串 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nohas(){ if printf '%s\n' "$2" | grep -qF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }

JAVA_T=
if command -v javac >/dev/null && [ -f "${TB321FU_DATA:-$REPO/../tb321fu_pixelos_15_tangorpro_ap3a.241005.015}/inputs/tools/pif-toolchain/android.jar" ]; then
  JAVA_T=$T/jcls; mkdir -p "$JAVA_T"
  javac -nowarn --release 17 -cp "${TB321FU_DATA:-$REPO/../tb321fu_pixelos_15_tangorpro_ap3a.241005.015}/inputs/tools/pif-toolchain/android.jar" -d "$JAVA_T" \
    "$REPO/patches/optional/devopts-hide/parts/001.hook/src/java/com/android/internal/os/SettingsCompatHelper.java" \
    "$REPO/patches/optional/devopts-hide/parts/001.hook/test/HelperTest.java" 2>/dev/null || JAVA_T=
fi

run() {   # run <sh> <命令…>   每条命令是 hide 的参数串
  local sh=$1; shift
  {
    echo "STATE=$T/state; blog() { :; }"
    echo ". $M/hide-control.sh"
    for c in "$@"; do echo "heraldp_cmd_hide '$c'; echo"; done
  } > "$T/drv.sh"
  HERALD_DH_STATE=$T/state HERALD_DH_CONF=$T/settings_compat.conf HERALD_DH_CHCON=${CHCON_STUB:-true} HERALD_DH_KMSG=/dev/null \
    HERALD_DH_APPLY="$sh $M/herald-devopts-hide.sh" HERALD_DH_MAX=${MAXN:-500} $sh "$T/drv.sh" 2>&1
}
boot() { HERALD_DH_STATE=$T/state HERALD_DH_CONF=$T/settings_compat.conf HERALD_DH_CHCON=true HERALD_DH_KMSG=/dev/null $1 "$M/herald-devopts-hide.sh" boot; }

suite() {
  local sh=$1 out
  echo "== $sh"; rm -rf "$T/state" "$T/settings_compat.conf"; mkdir -p "$T/state"
  out=$(run "$sh" "" "status")
  chk "默认 devopts=off" "$out" "devopts=off"
  out=$(run "$sh" "devopts")
  chk "默认 enabled" "$out" "enabled=0"; chk "默认 mode" "$out" "mode=list"; chk "默认 names" "$out" "names=0"
  chk "默认 rules_file" "$out" "rules_file=absent"; chk "默认 reboot" "$out" "reboot_required=0"
  has "keys" "$out" "adb_enabled"
  out=$(run "$sh" "devopts on"); has "空名单 on 的提示" "$out" "名单为空"; nohas "空名单不要求重启" "$out" "reboot-required"
  [ ! -e "$T/settings_compat.conf" ] && ok || bad "list + 空名单不该写配置文件"
  out=$(run "$sh" "devopts"); has "空名单 note" "$out" "note=list 模式名单为空"
  out=$(run "$sh" "devopts add com.bank.app" "devopts add com.bank.app" "devopts add com.x:remote" "devopts list")
  has "add" "$out" "ok devopts add com.bank.app reboot-required"; has "重复 add" "$out" "已在名单里"
  chk "list 含 1" "$out" "name=com.bank.app"; chk "list 含 2" "$out" "name=com.x:remote"; has "list mode" "$out" "mode=list"
  [ -f "$T/settings_compat.conf" ] && ok || bad "有名单后应写出配置文件"
  conf=$(cat "$T/settings_compat.conf" 2>/dev/null)
  chk "conf MODE" "$conf" "MODE=list"; chk "conf TARGET1" "$conf" "TARGET=com.bank.app"; chk "conf TARGET2" "$conf" "TARGET=com.x:remote"
  for k in development_settings_enabled adb_enabled adb_wifi_enabled wait_for_debugger mock_location; do chk "conf OVER.$k" "$conf" "OVER.$k=0"; done
  [ "$(stat -c %a "$T/settings_compat.conf")" = 600 ] && ok || bad "配置文件权限应为 600"
  [ ! -e "$T/settings_compat.conf.new" ] && ok || bad "不该留 .new"
  [ -n "$JAVA_T" ] && { r=$(java -cp "$JAVA_T" com.android.internal.os.HelperTest "$T/settings_compat.conf"); [ "$r" = "all=false names=2 over=5" ] && ok || bad "Java 解析结果: $r"; }
  out=$(run "$sh" "devopts"); chk "on 后 enabled" "$out" "enabled=1"; chk "names=2" "$out" "names=2"; chk "rules_file=present" "$out" "rules_file=present"
  chk "没开机过 → 要重启" "$out" "reboot_required=1"
  boot "$sh"; out=$(run "$sh" "devopts"); chk "开机后不用重启" "$out" "reboot_required=0"
  [ -f "$T/state/devhide.boot" ] && ok || bad "boot 应留副本"
  run "$sh" "devopts add com.second" >/dev/null; out=$(run "$sh" "devopts"); chk "加了之后要重启" "$out" "reboot_required=1"
  run "$sh" "devopts remove com.second" >/dev/null; out=$(run "$sh" "devopts"); chk "加了又删回原样 = 不用重启" "$out" "reboot_required=0"
  out=$(run "$sh" "devopts remove com.never"); has "remove 不存在" "$out" "本来就不在名单里"
  out=$(run "$sh" "devopts remove com.bank.app" "devopts list"); nohas "remove 后" "$(printf '%s\n' "$out" | tail -4)" "name=com.bank.app"
  run "$sh" "devopts add com.bank.app" >/dev/null
  out=$(run "$sh" "devopts mode all" "devopts"); has "mode all" "$out" "ok devopts mode all reboot-required"; chk "mode=all" "$out" "mode=all"
  conf=$(cat "$T/settings_compat.conf"); chk "conf MODE=all" "$conf" "MODE=all"; chk "all 白名单 TARGET" "$conf" "TARGET=com.bank.app"
  [ -n "$JAVA_T" ] && { r=$(java -cp "$JAVA_T" com.android.internal.os.HelperTest "$T/settings_compat.conf"); [ "$r" = "all=true names=2 over=5" ] && ok || bad "Java 解析 all: $r"; }
  rm -f "$T/state/devhide.names"; run "$sh" "devopts mode all" >/dev/null
  [ -f "$T/settings_compat.conf" ] && ok || bad "all 模式空白名单也应写配置文件"
  [ -n "$JAVA_T" ] && { r=$(java -cp "$JAVA_T" com.android.internal.os.HelperTest "$T/settings_compat.conf"); [ "$r" = "all=true names=0 over=5" ] && ok || bad "Java 解析 all 空名单: $r"; }
  out=$(run "$sh" "devopts mode list" "devopts"); chk "回 list" "$out" "mode=list"
  [ ! -e "$T/settings_compat.conf" ] && ok || bad "list + 空名单 → 删配置文件"
  run "$sh" "devopts add com.a" >/dev/null
  out=$(run "$sh" "devopts off" "devopts"); has "off" "$out" "ok devopts off reboot-required"; chk "off 后 enabled" "$out" "enabled=0"
  [ ! -e "$T/settings_compat.conf" ] && ok || bad "off 要删配置文件"
  out=$(run "$sh" "devopts"); chk "off 但开机时开着 → 要重启" "$out" "reboot_required=1"
  boot "$sh"; [ ! -e "$T/state/devhide.boot" ] && ok || bad "关着开机应删副本"
  out=$(run "$sh" "devopts"); chk "关着开机后不用重启" "$out" "reboot_required=0"
  out=$(run "$sh" "devopts add" "devopts add a/b" "devopts add .x" "devopts add a..b" "devopts add a@b" "devopts mode" "devopts mode x" "devopts frob" "devopts ADD" "frob")
  [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 10 ] && ok || { bad "非法输入全拒绝(期望 10 个 err)"; echo "$out" | sed 's/^/      | /'; }
  out=$(run "$sh" "devopts reset" "devopts"); has "reset" "$out" "ok devopts reset"; chk "reset 后 mode" "$out" "mode=list"; chk "reset 后 names" "$out" "names=0"; chk "reset 后 enabled" "$out" "enabled=0"
  [ ! -e "$T/state/devhide.conf" ] && [ ! -e "$T/state/devhide.names" ] && ok || bad "reset 要删状态文件"
  out=$(MAXN=2 run "$sh" "devopts add a1" "devopts add a2" "devopts add a3"); has "名单上限" "$out" "err 名单已满(2 条)"
  rm -rf "$T/state"; mkdir -p "$T/state"; run "$sh" "devopts add com.b" "devopts on" >/dev/null
  rm -f "$T/settings_compat.conf"; CHCON_STUB=false run "$sh" "devopts add com.c" >/dev/null
  [ -f "$T/settings_compat.conf" ] && ok || bad "chcon 失败也要写出文件(只记日志)"
  cat >/dev/null <<<""
}
command -v dash >/dev/null && suite dash
command -v busybox >/dev/null && suite "busybox sh"
echo "通过 $pass 项, 失败 $fail 项"
[ "$fail" = 0 ]
