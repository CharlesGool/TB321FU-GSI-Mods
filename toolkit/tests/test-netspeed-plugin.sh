#!/usr/bin/env bash
# statusbar-netspeed/control 插件的单元测试:herald_sys 桩成一个文件做的假 Settings.Global,dash 和 busybox sh 各跑一遍。
# 用法: toolkit/test-netspeed-plugin.sh   (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/patches/optional/statusbar-netspeed/parts/002.control/files
T=$(mktemp -d "${TMPDIR:-/tmp}/nstest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
has()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok; else bad "$1: 缺子串 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }

run() {   # run <sh> <命令…>
  local sh=$1; shift
  {
    echo "ST=$T/settings; touch \$ST"
    cat <<'STUB'
herald_sys() {   # 假的 settings:/system/bin/settings get|put|delete global 键 [值]
  [ "$1" = /system/bin/settings ] || return 1
  [ -n "${NS_FAIL:-}" ] && [ "$2" = put ] && return 1
  case "$2" in
    get) v=$(sed -n "s/^$4=//p" "$ST" | tail -1); echo "${v:-null}" ;;
    put) grep -v "^$4=" "$ST" > "$ST.n"; echo "$4=$5" >> "$ST.n"; mv "$ST.n" "$ST" ;;
    delete) grep -v "^$4=" "$ST" > "$ST.n"; mv "$ST.n" "$ST" ;;
  esac
}
STUB
    echo ". $M/speed-control.sh"
    for c in "$@"; do echo "heraldp_cmd_netspeed '$c'; echo"; done
  } > "$T/drv.sh"
  $sh "$T/drv.sh" 2>&1
}

suite() {
  local sh=$1 out
  echo "== $sh"; rm -f "$T/settings"
  out=$(run "$sh" "status" "")
  chk "默认 enabled" "$out" "enabled=1"; chk "默认 pos" "$out" "pos=end"; chk "默认 mode" "$out" "mode=both"; chk "默认 unit" "$out" "unit=bytes"
  [ "$(printf '%s\n' "$out" | grep -c '^ok 状态栏网速')" = 2 ] && ok || bad "空参数 = status"
  out=$(run "$sh" "off")
  grep -qx 'herald_netspeed=0' "$T/settings" && ok || bad "off 写 0"
  has "off 回包" "$out" "ok 已关闭"
  out=$(run "$sh" "status"); chk "off 后 status" "$out" "enabled=0"
  out=$(run "$sh" "on"); grep -qx 'herald_netspeed=1' "$T/settings" && ok || bad "on 写 1"
  out=$(run "$sh" "pos start" "mode down" "unit bits" "status")
  has "pos" "$out" "ok 位置 start"; has "mode" "$out" "ok 模式 down"; has "unit" "$out" "ok 单位 bits"
  chk "改后 pos" "$out" "pos=start"; chk "改后 mode" "$out" "mode=down"; chk "改后 unit" "$out" "unit=bits"
  out=$(run "$sh" "mode total" "status"); chk "total" "$out" "mode=total"
  out=$(run "$sh" "pos" "pos middle" "mode" "mode fast" "unit" "unit hex" "frob" "ADD")
  [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 8 ] && ok || { bad "非法参数全拒绝(期望 8 个 err)"; echo "$out" | sed 's/^/      | /'; }
  out=$(run "$sh" "reset" "status")
  has "reset" "$out" "ok 已恢复默认"; chk "reset 后 pos" "$out" "pos=end"; chk "reset 后 mode" "$out" "mode=both"
  [ ! -s "$T/settings" ] && ok || bad "reset 后四个键都应删掉"
  out=$(NS_FAIL=1 run "$sh" "on" "pos start")
  [ "$(printf '%s\n' "$out" | grep -c '^err 写')" = 2 ] && ok || bad "写失败要报 err"
}
command -v dash >/dev/null && suite dash
command -v busybox >/dev/null && suite "busybox sh"
echo "通过 $pass 项, 失败 $fail 项"
[ "$fail" = 0 ]
