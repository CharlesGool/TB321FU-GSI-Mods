#!/usr/bin/env bash
# google-slim 的磁贴清理:精简掉依赖的应用才去掉磁贴并生成 overlay;GOOGLE_SLIM=0 不精简就什么都不做。假树里跑,要 sudo。
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); TOOLKIT=$REPO/toolkit
MOD=$REPO/patches/required/tangorpro/tangorpro_ap3a.241005.015/slim/google-slim
T=$(mktemp -d); trap 'sudo rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1"; fi; }
run() { SYS=$T/system; sudo rm -rf "$SYS" "$T/work"; mkdir -p "$SYS/product/overlay" "$SYS/product/priv-app" "$T/work"; mkdir -p "$SYS/product/priv-app/GoogleHomePrebuilt" "$SYS/product/app/PrebuiltDeskClockGoogle_1"; echo 'ro.system.build.fingerprint=google/tangorpro/tangorpro:15/AP3A.241005.015/12366759:user/release-keys' > "$SYS/build.prop"
        ( export GOOGLE_SLIM=$1 SYS BUILD_STATE=$T/state MOD_NAME=t MOD TOOLKIT WORK=$T/work; rm -rf "$BUILD_STATE"; mkdir -p "$BUILD_STATE"
          bash -c 'source "$TOOLKIT/lib/common.sh"; source "$MOD/apply.sh"; :' ) > "$T/log" 2>&1; }
run 1
ok "1 级 Google Home 被精简:去掉 controls" 'grep -q "去掉磁贴: controls wallet" "$T/log"'
ok "新列表没有 controls 但别的还在" 'grep -q "新默认列表: internet,bt,rotation,mictoggle" "$T/log" && ! grep "新默认列表" "$T/log" | grep -q controls'
ok "编辑页总表也去掉 controls 和 wallet,cast 保留" 'grep "新内置总表" "$T/log" | grep -q "cast" && ! grep "新内置总表" "$T/log" | grep -qE "controls|wallet"'
ok "生成了 overlay" '[[ -f $SYS/product/overlay/herald-qs-tiles-clean.apk ]]'
run 0
ok "0 级不精简:什么都不做" '[[ -e $SYS/product/priv-app/GoogleHomePrebuilt && ! -e $SYS/product/overlay/herald-qs-tiles-clean.apk ]]'
run 2
ok "2 级:闹钟磁贴也去掉(时钟被精简)" 'grep "新内置总表" "$T/log" | grep -qv alarm && grep -q "去掉磁贴: controls.*alarm\|去掉磁贴: alarm" "$T/log"'
run 1
ok "1 级:闹钟磁贴保留" 'grep "新内置总表" "$T/log" | grep -q alarm'
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
