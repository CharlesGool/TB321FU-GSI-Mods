#!/usr/bin/env bash
# 产物名后缀:只有 required → 空;选了 optional/ → _optional;选了 debug/ → _debug;都选 → _optional_debug
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd); TOOLKIT=$REPO/toolkit; DEVICE_DIR=$REPO/devices/tb321fu-a15
pass=0 fail=0
chk() { # <说明> <期望> <PROFILE> <WITH> <WITHOUT>
    local got
    got=$( (PROFILE=$3 WITH=$4 WITHOUT=$5; export PROFILE WITH WITHOUT; REPO=$REPO; source "$DEVICE_DIR/device.conf" >/dev/null 2>&1; source "$TOOLKIT/lib/select.sh"; select_resolve >/dev/null 2>&1; select_flavor) )
    if [[ $got == "$2" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1: 期望 [$2] 得到 [$got]"; fi
}
printf -- '-all\n+required\n' > "$REPO/devices/tb321fu-a15/profiles/_t-required.txt"
printf -- '-all\n+required\n+optional/statusbar-netspeed\n' > "$REPO/devices/tb321fu-a15/profiles/_t-opt.txt"
printf -- '-all\n+required\n+debug/herald-ush\n' > "$REPO/devices/tb321fu-a15/profiles/_t-dbg.txt"
printf -- '-all\n+required\n+optional/statusbar-netspeed\n+debug/herald-ush\n' > "$REPO/devices/tb321fu-a15/profiles/_t-both.txt"
chk "只有 required" "" _t-required "" ""
chk "选了 optional" "_optional" _t-opt "" ""
chk "选了 debug" "_debug" _t-dbg "" ""
chk "optional 和 debug" "_optional_debug" _t-both "" ""
chk "required 加 WITH optional" "_optional" _t-required "optional/statusbar-netspeed" ""
rm -f "$REPO"/devices/tb321fu-a15/profiles/_t-*.txt
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
