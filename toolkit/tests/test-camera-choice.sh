#!/usr/bin/env bash
# 相机三选一:CAMERA=zui|pixel|none,默认 pixel;选相机不带 _optional 后缀
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd); TOOLKIT=$REPO/toolkit; DEVICE_DIR=$REPO/devices/tb321fu-a15
pass=0 fail=0
printf -- '-all\n+required\n' > "$DEVICE_DIR/profiles/_t-required.txt"
chk() { # <说明> <期望(zui/pixel 的有无,如 "zui pixel")> <CAMERA 或空=默认> <PROFILE> <WITH>
    local got
    got=$( (unset CAMERA; [[ -n $3 ]] && CAMERA=$3; PROFILE=$4 WITH=$5; export PROFILE WITH; REPO=$REPO; source "$DEVICE_DIR/device.conf" >/dev/null 2>&1; source "$TOOLKIT/lib/select.sh"; select_resolve >/dev/null 2>&1
        for m in "${SEL_MODS[@]}"; do case $m in */zuicamera) echo -n "zui ";; */pixel-camera) echo -n "pixel ";; esac; done; [[ -n $PROFILE ]] && echo "|$(select_flavor)" || echo "|") )
    if [[ $got == "$2" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1: 期望 [$2] 得到 [$got]"; fi
}
chk "默认只有 Pixel 相机" "pixel |" "" "" ""
chk "CAMERA=zui" "zui |" zui "" ""
chk "CAMERA=pixel" "pixel |" pixel "" ""
chk "CAMERA=none" "|" none "" ""
chk "required-only 预设里也只有一个" "pixel |" "" _t-required ""
chk "required-only + CAMERA=zui" "zui |" zui _t-required ""
chk "WITH 仍可以两个都装" "zui pixel |" none "" "zuicamera,pixel-camera"
rm -f "$DEVICE_DIR"/profiles/_t-*.txt
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
