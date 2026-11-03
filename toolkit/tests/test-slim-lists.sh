#!/usr/bin/env bash
# 通用精简脚本(toolkit/lib/removelist.sh):底包 ID、slim_apply 按文件名顺序跑每份 .list、通配符、没有的条目只记日志、非法路径拒绝。
# 用法: toolkit/tests/test-slim-lists.sh      (在临时目录里用假树,要 sudo)
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOLKIT=$REPO/toolkit
T=$(mktemp -d); trap 'sudo rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1"; fi; }

mk_tree() {   # mk_tree <指纹>
    SYS=$T/system; sudo rm -rf "$SYS"; mkdir -p "$SYS/product/app/CalculatorGooglePrebuilt_999" "$SYS/product/app/Keep" "$SYS/product/app/A" "$SYS/product/app/B" "$SYS/etc"
    echo "ro.system.build.fingerprint=$1" > "$SYS/build.prop"
}
run() {   # run <lists 目录>   → 日志在 $T/log
    ( export SYS BUILD_STATE=$T/state MOD_NAME=t; rm -rf "$BUILD_STATE"; mkdir -p "$BUILD_STATE"
      source "$TOOLKIT/lib/common.sh"; source "$TOOLKIT/lib/removelist.sh"; slim_apply "$1" ) > "$T/log" 2>&1
}
L=$T/lists; mkdir -p "$L"
printf '# c\nproduct/app/CalculatorGooglePrebuilt_*\nproduct/app/NoSuch_*\n' > "$L/a.list"
printf 'product/app/A\n' > "$L/b.list"

mk_tree 'google/tangorpro/tangorpro:15/AP3A.241005.015/12366759:user/release-keys'
run "$L"
ok "底包 ID 取自指纹" 'grep -q "底包 ID: tangorpro_ap3a.241005.015_12366759" "$T/log"'
ok "通配删掉带版本号的目录" '[[ ! -e $SYS/product/app/CalculatorGooglePrebuilt_999 ]]'
ok "每份清单都跑" '[[ ! -e $SYS/product/app/A && -e $SYS/product/app/B && -e $SYS/product/app/Keep ]]'
ok "没有的条目只记日志" 'grep -q "(没有) product/app/NoSuch_\*" "$T/log"'
ok "每份清单一行统计" '[[ $(grep -c "^  \[t\] 清单 " "$T/log") == 2 ]]'

mk_tree 'google/tangorpro/tangorpro:15/AP3A.241005.015/1:user/release-keys'
printf '../etc\n' > "$L/z.list"; run "$L"
ok "含 .. 的路径被拒绝" 'grep -q "路径不合法" "$T/log"'
rm -f "$L/z.list"
mkdir -p "$T/empty"; run "$T/empty"
ok "目录里没有 .list 会停" 'grep -q "一份 .list 都没有" "$T/log"'
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
