#!/usr/bin/env bash
# custom-font/control 的单元测试:插件和开机保护脚本都在临时目录里跑(chcon、dmesg、系统字体目录都桩掉),
# dash 和 busybox sh 各一遍。用法: toolkit/test-font-plugin.sh  (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/patches/optional/custom-font/parts/002.control/files
T=$(mktemp -d "${TMPDIR:-/tmp}/fonttest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
has()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok; else bad "$1: 缺子串 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nohas(){ if printf '%s\n' "$2" | grep -qF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }

# 假的系统字体目录和导入目录
mkdir -p "$T/stock1" "$T/stock2" "$T/imp"
echo a > "$T/stock1/Roboto-Regular.ttf"; echo b > "$T/stock1/NotoSerif-Regular.ttf"; echo c > "$T/stock2/GoogleSans-Regular.ttf"
mkpack() {   # mkpack <目录> <xml 里引用的文件…>   造一个包目录,第一个参数后面的文件如果是 own: 前缀就放进包里
  local d=$1; shift; mkdir -p "$d"
  { echo '<familyset>'; for f in "$@"; do echo "<font>${f#own:}</font>"; done; echo '</familyset>'; } > "$d/font_fallback.xml"
  for f in "$@"; do case "$f" in own:*) echo x > "$d/${f#own:}" ;; esac; done
}

run() {   # run <sh> <font 参数串…>
  local sh=$1; shift
  {
    echo "blog() { :; }"
    echo ". $M/font-control.sh"
    for c in "$@"; do echo "heraldp_cmd_font '$c'; echo"; done
  } > "$T/drv.sh"
  HERALD_FONT_ROOT=$T/root HERALD_FONT_STOCK_DIRS="$T/stock1 $T/stock2" HERALD_FONT_IMPORT_ROOTS="$T/imp/" \
    HERALD_FONT_CHCON="$T/chcon.sh" HERALD_FONT_MAX_KB=${MAXKB:-262144} $sh "$T/drv.sh" 2>&1
}
boot() { HERALD_FONT_ROOT=$T/root HERALD_FONT_KMSG=/dev/null $1 "$M/herald-font.sh" boot; }
bootok() { HERALD_FONT_ROOT=$T/root HERALD_FONT_KMSG=/dev/null $1 "$M/herald-font.sh" ok; }

suite() {
  local sh=$1 out
  echo "== $sh"; rm -rf "$T/root" "$T/chcon.log"; find "$T/imp" -mindepth 1 -delete
  printf '#!/bin/sh\necho "$@" >> %s/chcon.log\n' "$T" > "$T/chcon.sh"; chmod +x "$T/chcon.sh"
  out=$(run "$sh" "" "status")
  chk "默认 active" "$out" "active=none"; chk "默认 packs" "$out" "packs=0"; chk "默认 reboot" "$out" "reboot_required=0"
  out=$(run "$sh" "list"); chk "list 空" "$out" "ok font list"; nohas "list 空没有包" "$out" "pack="

  # 装目录包:自带 My-Regular.ttf,引用的 Roboto-Regular.ttf / GoogleSans-Regular.ttf 靠符号链接补
  mkpack "$T/imp/mypack" own:My-Regular.ttf Roboto-Regular.ttf GoogleSans-Regular.ttf
  out=$(run "$sh" "install $T/imp/mypack")
  has "install 目录" "$out" "ok font install mypack"
  [ -f "$T/root/packs/mypack/My-Regular.ttf" ] && ok || bad "包里自带的字体"
  [ -L "$T/root/packs/mypack/Roboto-Regular.ttf" ] && ok || bad "系统字体应是符号链接"
  [ "$(readlink "$T/root/packs/mypack/GoogleSans-Regular.ttf")" = "$T/stock2/GoogleSans-Regular.ttf" ] && ok || bad "链接指向第二个系统目录"
  [ -L "$T/root/packs/mypack/NotoSerif-Regular.ttf" ] && ok || bad "没引用的系统字体也补链接"
  grep -q -- '-R -h u:object_r:font_data_file:s0' "$T/chcon.log" 2>/dev/null && ok || bad "chcon 要带 -R -h 和 font_data_file"
  out=$(run "$sh" "list"); chk "list 里完整" "$out" "pack=mypack valid=yes active=0 kb=$(du -sk "$T/root/packs/mypack" | cut -f1)"

  # 缺文件的包
  mkpack "$T/imp/broken" own:Mine.ttf Missing-Font.ttf
  out=$(run "$sh" "install $T/imp/broken"); has "缺文件" "$out" "err 包不完整,缺: Missing-Font.ttf"
  [ ! -e "$T/root/packs/broken" ] && ok || bad "缺文件的包不该留下"
  mkdir -p "$T/imp/noxml"; echo x > "$T/imp/noxml/a.ttf"
  out=$(run "$sh" "install $T/imp/noxml"); has "没有 xml" "$out" "err 包里没有 font_fallback.xml"

  # zip 包
  python3 - "$T" <<'PY'
import sys, zipfile
t = sys.argv[1]
with zipfile.ZipFile(t + '/imp/zpack.zip', 'w') as z:
    z.writestr('font_fallback.xml', '<familyset><font>Z-Regular.ttf</font><font>NotoSerif-Regular.ttf</font></familyset>')
    z.writestr('Z-Regular.ttf', 'zz')
with zipfile.ZipFile(t + '/imp/nox.zip', 'w') as z:
    z.writestr('a.ttf', 'x')
PY
  out=$(run "$sh" "install $T/imp/zpack.zip"); has "install zip" "$out" "ok font install zpack"
  out=$(run "$sh" "install $T/imp/nox.zip"); has "zip 没 xml" "$out" "err 包里没有 font_fallback.xml"
  out=$(run "$sh" "install $T/imp/zpack.zip renamed"); has "指定名字" "$out" "ok font install renamed"
  out=$(run "$sh" "install $T/imp/not-a-zip.zip"); has "不存在" "$out" "err 找不到"
  echo notzip > "$T/imp/bad.zip"; out=$(run "$sh" "install $T/imp/bad.zip"); has "不是 zip" "$out" "err 解压失败"

  # 来源和名字限制
  out=$(run "$sh" "install /etc/passwd" "install $T/imp/../x" "install $T/imp/mypack bad/name" "install $T/imp/mypack .hid" "install")
  [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 5 ] && ok || { bad "非法来源/名字全拒绝(期望 5 个 err)"; echo "$out" | sed 's/^/      | /'; }
  out=$(MAXKB=0 run "$sh" "install $T/imp/mypack big"); has "超大小" "$out" "err 包太大"
  [ ! -e "$T/root/packs/big" ] && ok || bad "超大小不该留下"

  # use / 重启判断 / 开机保护
  out=$(run "$sh" "use nosuch" "use bad/n" "use"); [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 3 ] && ok || bad "use 非法全拒绝"
  out=$(run "$sh" "use mypack" "status"); has "use" "$out" "ok font use mypack reboot-required"; chk "active" "$out" "active=mypack"; chk "要重启" "$out" "reboot_required=1"
  boot "$sh"
  [ -f "$T/root/boot_try" ] && ok || bad "boot 要放 boot_try"
  out=$(run "$sh" "status"); chk "开机后不用重启" "$out" "reboot_required=0"; chk "active 仍在" "$out" "active=mypack"
  bootok "$sh"; [ ! -e "$T/root/boot_try" ] && ok || bad "ok 要删 boot_try"
  boot "$sh"; [ -f "$T/root/boot_try" ] && ok || bad "正常再开机仍放 boot_try"
  # 这次开机没走完(没跑 ok)→ 下次 boot 撤回
  boot "$sh"
  [ ! -e "$T/root/active" ] && ok || bad "没走完的开机要撤回 active"
  [ ! -e "$T/root/boot_try" ] && ok || bad "撤回后 boot_try 要清掉"
  out=$(run "$sh" "status"); chk "reverted 记名" "$out" "reverted=mypack"; chk "撤回后 active" "$out" "active=none"; chk "撤回后不用重启" "$out" "reboot_required=0"
  out=$(run "$sh" "use mypack" "status"); nohas "use 清掉 reverted" "$out" "reverted="

  # check / reset / remove
  rm -f "$T/root/packs/mypack/My-Regular.ttf"
  out=$(run "$sh" "check mypack"); has "check 不完整" "$out" "不完整"; chk "check missing" "$out" "missing=My-Regular.ttf"
  out=$(run "$sh" "use mypack"); has "use 不完整" "$out" "err 包不完整,缺: My-Regular.ttf"
  out=$(run "$sh" "check zpack"); has "check 完整" "$out" "ok zpack 完整"
  run "$sh" "use zpack" >/dev/null; boot "$sh"; bootok "$sh"
  out=$(run "$sh" "remove zpack"); has "remove 正在用" "$out" "err zpack 正在使用"
  out=$(run "$sh" "reset" "status"); has "reset" "$out" "ok font reset reboot-required"; chk "reset 后 active" "$out" "active=none"; chk "reset 后要重启" "$out" "reboot_required=1"
  out=$(run "$sh" "reset"); has "重复 reset" "$out" "本来就是系统字体"
  out=$(run "$sh" "remove mypack" "remove mypack" "list"); has "remove" "$out" "ok font remove mypack"; has "remove 不存在" "$out" "本来就没有"
  [ ! -e "$T/root/packs/mypack" ] && ok || bad "remove 要删目录"
  [ -d "$T/stock1" ] && [ -f "$T/stock1/Roboto-Regular.ttf" ] && ok || bad "remove 不能碰系统字体"
  out=$(run "$sh" "frob" "STATUS" "" ); [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 2 ] && ok || bad "未知子命令 err"
  # 开机脚本在没有目录时安静退出
  rm -rf "$T/root"; boot "$sh" && ok || bad "没有目录时 boot 应安静退出"
}
command -v dash >/dev/null && suite dash
command -v busybox >/dev/null && suite "busybox sh"
echo "通过 $pass 项, 失败 $fail 项"
[ "$fail" = 0 ]
