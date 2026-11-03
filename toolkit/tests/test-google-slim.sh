#!/usr/bin/env bash
# slim/google-slim 分级:GOOGLE_SLIM=0 不删、1 冷门、2 加日常、3 加无障碍;非法值报错。假树里跑,要 sudo。
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); TOOLKIT=$REPO/toolkit
MOD=$REPO/patches/required/tangorpro/tangorpro_ap3a.241005.015/slim/google-slim
T=$(mktemp -d); trap 'sudo rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1"; fi; }
mk() { SYS=$T/system; sudo rm -rf "$SYS"; mkdir -p "$SYS/product/app/YouTubeKidsPrebuilt" "$SYS/product/app/PrebuiltDeskClockGoogle_1" "$SYS/product/app/talkback" "$SYS/product/app/Keep0"
       echo "ro.system.build.fingerprint=google/tangorpro/tangorpro:15/AP3A.241005.015/12366759:user/release-keys" > "$SYS/build.prop"; }
run() { mk; ( export SYS BUILD_STATE=$T/state MOD_NAME=t MOD TOOLKIT GOOGLE_SLIM=$1; rm -rf "$BUILD_STATE"; mkdir -p "$BUILD_STATE"
      bash -c 'source "$TOOLKIT/lib/common.sh"; source "$MOD/apply.sh"; :' ) > "$T/log" 2>&1; }
has() { [[ -e $SYS/product/app/$1 ]]; }
run 0; ok "0 什么都不删" 'has YouTubeKidsPrebuilt && has PrebuiltDeskClockGoogle_1 && has talkback'
run 1; ok "1 只删冷门" '! has YouTubeKidsPrebuilt && has PrebuiltDeskClockGoogle_1 && has talkback'
run 2; ok "2 加日常" '! has YouTubeKidsPrebuilt && ! has PrebuiltDeskClockGoogle_1 && has talkback'
run 3; ok "3 加无障碍" '! has YouTubeKidsPrebuilt && ! has PrebuiltDeskClockGoogle_1 && ! has talkback'
run 9; ok "非法级别报错" 'grep -q "GOOGLE_SLIM 只能是" "$T/log"'
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
