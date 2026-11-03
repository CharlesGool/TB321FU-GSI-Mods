#!/usr/bin/env bash
# herald-start.sh(核心)+ 00-attestation.sh(引擎插件)开机前半段(到起 keymint 守护之前)在 set -u 下的回归测试:按 App 伪装 + 伪装开着,
# 不能因为未定义变量退出(V84 真机:$DATA_PIF 在定义前使用,后端起不来)。不碰真机。用法: toolkit/test-herald-start-prefix.sh
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
F=$REPO/patches/required/general/herald-core/files/herald-start.sh; E=$REPO/patches/required/general/attestation-fix/files/00-attestation.sh
SEEDCFG=$(ls "${TB321FU_DATA:-$REPO/../tb321fu_pixelos_15_tangorpro_ap3a.241005.015}"/legacy/gsi/strong/herald-payload/seed/config.toml)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "  FAIL: $*"; }
N=$(grep -n '^# ---- 守护:keymint' "$E" | cut -d: -f1)
for mode in app global off; do
  for SH in dash "busybox sh"; do
    command -v ${SH%% *} >/dev/null || continue
    rm -rf "$T/x"; mkdir -p "$T/x"/{pay/bin,pay/seed,pay/app-spoof,cfg/data,state,bin}
    cp "$SEEDCFG" "$T/x/pay/seed/"; touch "$T/x/pay/app-spoof/targets.default"
    # V92:真实设备 profile 只有 model/product/fingerprint/security_patch,brand/device/manufacturer 要从 fingerprint 推
    #   (V84–V90 的 bug:直接读 json 读到空 → config.toml [device] 没被改 → Play -66)
    echo '{"model":"Pixel 6a","product":"bluejay_beta","fingerprint":"google\/bluejay_beta\/bluejay:CANARY\/ZP11.260918.007\/16484274:user\/release-keys","security_patch":"2026-10-05"}' > "$T/x/cfg/data/pif_fingerprint.json"
    [ "$mode" != off ] && touch "$T/x/cfg/data/global_pif_enabled"
    [ "$mode" = global ] && echo global > "$T/x/cfg/data/spoof_mode"
    printf '#!/bin/sh\necho "$@" >> %s/rp.log\n' "$T/x" > "$T/x/bin/resetprop"; printf '#!/bin/sh\necho real\n' > "$T/x/bin/getprop"; chmod +x "$T/x/bin/"*
    { sed -n '1,/^mkdir -p "\$STATE"/p' "$F"; sed -n "1,$((N-1))p" "$E"; echo 'echo "PREFIX-DONE swapped=$IDS_SWAPPED"'; echo '}'; echo 'heraldp_start_attestation'; } \
      | sed -e "s#/system/etc/herald_payload#$T/x/pay#g" -e "s#/data/misc/keystore/herald#$T/x/cfg#g" -e "s#/data/adb/herald#$T/x/state#g" -e "s#BIN=\$PAYDIR/bin#BIN=$T/x/bin#" -e '/^chown/d' -e 's#/metadata/herald_log#'"$T"'/x/meta#g' > "$T/x/pre.sh"
    o=$(PATH=$T/x/bin:$PATH $SH "$T/x/pre.sh" 2>&1)
    if echo "$o" | grep -q "PREFIX-DONE"; then ok; else bad "$mode/$SH: 开机前半段没跑完"; echo "$o" | tail -3 | sed 's/^/      | /'; fi
    # V92:app 模式开设备 ID 属性窗口(swapped=1,启动登记 google/登记后改回);global/off 不开(swapped=0)
    want_sw=0; [ "$mode" = app ] && want_sw=1
    echo "$o" | grep -q "PREFIX-DONE swapped=$want_sw" && ok || bad "$mode/$SH: swapped 应为 $want_sw"
    m=$(sed -n '/^\[device\]/,/^\[main/{s/^manufacturer = "\(.*\)"/\1/p}' "$T/x/cfg/config.toml" 2>/dev/null | tr -d '\r')
    d=$(sed -n '/^\[device\]/,/^\[main/{s/^device = "\(.*\)"/\1/p}' "$T/x/cfg/config.toml" 2>/dev/null | tr -d '\r')
    want_m=Lenovo; want_d=TB321FU; [ "$mode" = app ] && { want_m=Google; want_d=bluejay; }
    [ "$m" = "$want_m" ] && ok || bad "$mode/$SH: config manufacturer=$(printf %s "$m" | od -c | head -2) 应为 $want_m"
    [ "$d" = "$want_d" ] && ok || bad "$mode/$SH: config device=$d 应为 $want_d(从 fingerprint 推)"
  done
done
echo "通过 $pass,失败 $fail"; [ "$fail" = 0 ]
