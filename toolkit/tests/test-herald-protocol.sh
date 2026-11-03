#!/usr/bin/env bash
# 免 root 核心协议回归测试:在模拟环境里跑真正的 herald-start.sh 和 heraldctl,断言命令回包的格式没变。
#
# 用法: toolkit/test-herald-protocol.sh <device.conf> [--baseline <旧版 herald-start.sh> <旧版 heraldctl>]
#   不给 --baseline:只检查回包格式约定(接口文档里写的那些)。
#   给了 --baseline:另外把旧版和当前版放在同一个模拟环境里跑同一批命令,回包必须逐字节相同
#                   (heraldctl help 里插件加进来的命令说明除外)。
#
# 为什么要有这个:前端 App 按文档里的格式解析回包,后端改动不能悄悄改格式。V67 就出过一次——
# keymint 的输出末尾没有换行时,`spoof get` 末尾的 `HERALD_GLOBAL_PIF_FLAG=…` 会粘在 JSON 后面,前端读不到。
#
# 模拟环境:把脚本里的 /data/、/system/bin/ 等路径改写到临时目录,假的 keymint/settings/cmd/dumpsys/wm,
# 不需要设备、不需要 root。keymint 的输出末尾"有换行"和"没换行"两种都测。
set -euo pipefail
CONF=$(realpath "$1"); shift
BASE_START=; BASE_CTL=
if [[ ${1:-} == --baseline ]]; then BASE_START=$(realpath "$2"); BASE_CTL=$(realpath "$3"); shift 3; fi
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$(dirname "$HERE")")
# shellcheck disable=SC1090
source "$CONF"
: "${HERALD_PAYLOAD:?device.conf 没设 HERALD_PAYLOAD}"
T=$(mktemp -d); [[ -n ${KEEP:-} ]] && echo "保留现场: $T"; trap 'pkill -f "$T/" 2>/dev/null || true; [[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT
CUR_START=$REPO/patches/required/general/herald-core/files/herald-start.sh; CUR_CTL=$REPO/patches/required/general/herald-core/files/heraldctl; NAVDIR=$REPO/patches/optional/navbar-hide/parts/004.control/files
ENGDIR=$REPO/patches/required/general/attestation-fix/files; WIFIDIR=$REPO/patches/optional/hotspot-control/parts/002.control/files

run_one() {  # run_one <标签> <herald-start.sh> <heraldctl> <navbar 插件目录或-> <nl|nonl> <输出文件>
    local L=$1 SC=$2 CT=$3 PLUG=$4 NLMODE=$5 OUTF=$6 F=$T/$1 BP
    mkdir -p "$F"/{bin,payload/bin,payload/seed,payload/plugins,payload/heraldctl.d,data/local/tmp,data/misc/keystore,data/adb,data/data}
    cp "$HERALD_PAYLOAD"/seed/* "$F/payload/seed/" 2>/dev/null || true
    if [[ $PLUG != - ]]; then sed -e "s#/system/bin/#$F/bin/#g" -e "s#/data/#$F/data/#g" "$PLUG/navbar.sh" > "$F/payload/plugins/navbar.sh"; cp "$PLUG/heraldctl-navbar.sh" "$F/payload/heraldctl.d/navbar.sh"; fi
    local JSON='{"enabled":true,"model":"Pixel Tablet","product":"tangorpro_beta","fingerprint":"google\/tangorpro_beta\/x:CANARY\/1\/2:user\/release-keys","security_patch":"2026-10-05"}'
    { echo '#!/bin/sh'; echo 'case "$1" in'
      echo "  --webui-get-pif-fingerprint-state) $( [[ $NLMODE == nl ]] && echo "echo '$JSON'" || echo "printf '%s' '$JSON'" ) ;;"
      echo "  --webui-list-pif-devices) echo '[{\"model\":\"Pixel 7\",\"product\":\"panther_beta\"}]' ;;"
      echo '  --webui-*) echo "ok $1" ;;'; echo '  *) sleep 3600 ;;'; echo 'esac'; } > "$F/payload/bin/keymint"
    { echo '#!/bin/sh'; echo 'sleep 3600'; } > "$F/payload/bin/inject"; printf '#!/bin/sh\nexit 0\n' > "$F/payload/bin/resetprop"
    for c in getprop setprop reboot logcat; do printf '#!/bin/sh\nexit 0\n' > "$F/bin/$c"; done
    printf '#!/bin/sh\nexit 1\n' > "$F/bin/pidof"
    printf '#!/bin/sh\ncase "$1" in get) echo 2;; *) exit 0;; esac\n' > "$F/bin/settings"
    # cmd wifi ...:记下收到的参数(每个参数一行,中间用 | 隔开,看引号有没有保住);navbar 的 cmd overlay 照旧
    { echo '#!/bin/sh'; echo 'if [ "$1" = wifi ]; then printf "%s" "$*" > "'"$F"'/wifi.args"; for a in "$@"; do printf "|%s" "$a"; done > "'"$F"'/wifi.args"; echo "SAP is enabled successfully"; exit 0; fi'
      echo 'echo "[ ] com.omk.navhide.android"; echo "[ ] com.omk.navhide.systemui"; echo "[ ] com.omk.navhide.launcher"'; } > "$F/bin/cmd"
    { echo '#!/bin/sh'; echo 'if [ "$1" = wifi ]; then [ -f "'"$F"'/ap_off" ] && { echo "Wi-Fi is enabled"; exit 0; }; echo "mCurrentSoftApInfoMap: {wlan1=SoftApInfo{bandwidth= 4, frequency= 5180, wifiStandard= 6}}"; exit 0; fi'
      echo 'echo "Window{abc Taskbar}"'; } > "$F/bin/dumpsys"
    printf '#!/bin/sh\ncase "$1" in size) echo "Physical size: 1600x2560";; density) echo "Physical density: 400";; esac\n' > "$F/bin/wm"
    chmod +x "$F"/bin/* "$F"/payload/bin/*
    # 核心拆分后,引擎(keymint 命令)和 Wi-Fi 命令是接入核心的插件;旧版(基线)是一个整体,不装
    if [[ $L == cur* ]]; then
        local RW=(-e 's#\$CFG/data/#$CFG/@D@/#g' -e "s#/data/#$F/data/#g" -e 's#@D@#data#g' -e "s#/system/bin/#$F/bin/#g")
        sed "${RW[@]}" "$ENGDIR/00-attestation.sh" > "$F/payload/plugins/00-attestation.sh"; cp "$ENGDIR/heraldctl-attestation.sh" "$F/payload/heraldctl.d/00-attestation.sh"
        sed "${RW[@]}" "$WIFIDIR/wifi.sh" > "$F/payload/plugins/wifi.sh"; cp "$WIFIDIR/heraldctl-wifi.sh" "$F/payload/heraldctl.d/wifi.sh"
    fi
    # V73 readonly-shell 插件(只在当前版装;旧版没有 rexec)。白名单程序用宿主机的真程序
    if [[ $L == cur* ]]; then
        local RS=$REPO/patches/debug/herald-readonly-shell/files
        sed -e "s#/system/bin/#$F/bin/#g" -e "s#/data/#$F/data/#g" -e "s#/system/etc/herald_payload#$F/payload#g" "$RS/readonly-shell.sh" > "$F/payload/plugins/readonly-shell.sh"
        cp "$RS/heraldctl-readonly-shell.sh" "$F/payload/heraldctl.d/readonly-shell.sh"
        for c in cat ls grep head; do ln -sf "$(command -v $c)" "$F/bin/$c"; done
        echo "hello rexec" > "$F/data/local/rx.txt"; echo "secret" > "$F/data/adb/secret.txt"
        # V75:大输出(真机 rexec dmesg 在 mksh 下 "Argument list too long")。400KB,超过单个参数上限 128KB,也超过 rexec 的 256KB 截断
        seq 1 70000 | sed 's/^/line /' > "$F/data/local/big.txt"
    fi
    sed -e 's#\$CFG/data/#$CFG/@D@/#g' -e "s#/data/#$F/data/#g" -e 's#@D@#data#g' -e "s#PAYDIR=/system/etc/herald_payload#PAYDIR=$F/payload#" -e "s#/system/bin/#$F/bin/#g" \
        -e "s#^SH_UIDS=.*#SH_UIDS=\"0 2000 $(id -u)\"#" "$SC" > "$F/herald-start.sh"
    sed -e 's#\$CFG/data/#$CFG/@D@/#g' -e "s#/data/#$F/data/#g" -e 's#@D@#data#g' -e "s#/system/etc/heraldctl.d#$F/payload/heraldctl.d#" "$CT" > "$F/heraldctl"
    PATH="$F/bin:$PATH" setsid sh "$F/herald-start.sh" > "$F/broker.out" 2>&1 & BP=$!
    local i; for i in $(seq 1 40); do [[ -d $F/data/adb/herald/work || -d $F/data/local/tmp/herald/.work ]] && break; sleep 0.5; done
    [[ -d $F/data/adb/herald/work || -d $F/data/local/tmp/herald/.work ]] || { echo "[$L] broker 没起来:"; head -5 "$F/broker.out"; kill -- -$BP 2>/dev/null; return 1; }
    ctl() { echo "## heraldctl $*"; HERALD_TIMEOUT=12 sh "$F/heraldctl" "$@" 2>&1 | cat -A | sed 's/\$$//'; }
    printf '{"model":"Pixel 7","fingerprint":"google/panther/panther:14/UP1A.231005.007/10754064:user/release-keys","brand":"google","device":"panther","manufacturer":"Google","product":"panther","release":"14","id":"UP1A","incremental":"1","security_patch":"2026-10-05"}\n' > "$F/prof.json"
    { ctl spoof get; ctl spoof list; ctl spoof set "$F/prof.json"; ctl spoof get; ctl spoof off; ctl spoof get
      if [[ $PLUG != - || $L == base* ]]; then ctl navbar status; fi; ctl pair; } > "$OUTF" 2>&1 || true
    # V68 新增:wifi show 的回复末尾附系统热点设置(sys_*)。旧版没有,所以单独存,不进逐字节对比。
    if [[ $L == cur* ]]; then
        mkdir -p "$F/data/misc/apexdata/com.android.wifi"
        cat > "$F/data/misc/apexdata/com.android.wifi/WifiConfigStoreSoftAp.xml" <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<WifiConfigStoreData>
<SoftAp>
<string name="WifiSsid">&quot;MyTab&amp;1&quot;</string>
<int name="SecurityType" value="3" />
<string name="Passphrase">pass&amp;word1</string>
<boolean name="HiddenSSID" value="false" />
<BandChannelMap>
<BandChannel>
<int name="Band" value="1" />
</BandChannel>
<BandChannel>
<int name="Band" value="2" />
</BandChannel>
</BandChannelMap>
<int name="MaxNumberOfClients" value="8" />
<boolean name="AutoShutdownEnabled" value="true" />
<long name="ShutdownTimeoutMillis" value="600000" />
<boolean name="ClientControlByUser" value="false" />
<int name="MacRandomizationSetting" value="1" />
</SoftAp>
</WifiConfigStoreData>
XML
        { ctl wifi show; } > "${OUTF%.txt}.wifi.txt" 2>&1 || true
        { ctl hotspot start-system; ctl hotspot status; touch "$F/ap_off"; ctl hotspot status; rm -f "$F/ap_off"; } > "${OUTF%.txt}.hs.txt" 2>&1 || true
        { ctl spoof patch 2025-05-05 all; ctl spoof patch 2025-05-05; } > "${OUTF%.txt}.pa.txt" 2>&1 || true
        rctl() { echo "## heraldctl $*"; HERALD_TIMEOUT=12 sh "$F/heraldctl" "$@" 2>&1; }
        { rctl rexec cat "$F/data/local/rx.txt"; rctl rexec on 5; rctl rexec cat "$F/data/local/rx.txt"; rctl rexec cat "$F/data/adb/secret.txt"
          rctl rexec rm "$F/data/local/rx.txt"; rctl rexec cat "$F/data/local/rx.txt; id"; rctl rexec ls "$F/data/local"; rctl rexec off; rctl rexec cat "$F/data/local/rx.txt"
        } > "${OUTF%.txt}.rx.txt" 2>&1 || true
        { HERALD_TIMEOUT=12 sh "$F/heraldctl" rexec on 5; HERALD_TIMEOUT=12 sh "$F/heraldctl" rexec cat "$F/data/local/big.txt"; } > "${OUTF%.txt}.big.txt" 2>&1 || true
        cp "$F/wifi.args" "${OUTF%.txt}.hs.args" 2>/dev/null || true
    fi
    kill -- -$BP 2>/dev/null || true; pkill -f "$F/" 2>/dev/null || true
}

FAIL=0
check() {
  if eval "$2"; then echo "  通过  $1"; else echo "  失败  $1"; FAIL=1; fi
}
for mode in nl nonl; do
    echo "==== keymint 输出$([[ $mode == nl ]] && echo 末尾有换行 || echo 末尾没有换行)"
    run_one cur_$mode "$CUR_START" "$CUR_CTL" "$NAVDIR" $mode "$T/cur_$mode.txt" || { FAIL=1; continue; }
    # 取每次 spoof get 的回包(## 开头到下一个 ##)里最后两行
    check "spoof get 末尾是单独一行 HERALD_GLOBAL_PIF_FLAG=on|off" \
        "awk 'function chk(){ if(f&&!(l ~ /^HERALD_GLOBAL_PIF_FLAG=(on|off)\$/)) bad=1 } /^## /{chk(); f=0; l=\"\"} /^## heraldctl spoof get/{f=1; n++; next} f&&NF{l=\$0} END{chk(); exit (bad||!n)}' '$T/cur_$mode.txt'"
    check "spoof get 里没有被转义的 \\/ (V72)" "! grep -F '\\/' '$T/cur_$mode.txt' | grep -v '^## ' | grep -q ."
    check "标记行没有粘在别的内容后面" "! grep -E '[^[:space:]]HERALD_GLOBAL_PIF_FLAG=' '$T/cur_$mode.txt' >/dev/null"
    check "spoof list 回包是 JSON 数组" "grep -A1 '^## heraldctl spoof list' '$T/cur_$mode.txt' | tail -1 | grep -q '^\\['"
    check "navbar status 第一行以 ok navbar 开头" "grep -A1 '^## heraldctl navbar status' '$T/cur_$mode.txt' | tail -1 | grep -q '^ok navbar '"
    check "wifi show 的回复:前面的行不变,末尾多出 sys_* 行(V68)" \
        "grep -q '^softap_info=' '$T/cur_$mode.wifi.txt' && grep -qx 'sys_ssid=MyTab&1' '$T/cur_$mode.wifi.txt' && grep -qx 'sys_pass=pass&word1' '$T/cur_$mode.wifi.txt' && grep -qx 'sys_band=3' '$T/cur_$mode.wifi.txt' && grep -qx 'sys_timeout_min=10' '$T/cur_$mode.wifi.txt' && grep -qx 'sys_sec=3' '$T/cur_$mode.wifi.txt'"
    check "hotspot start-system:用系统设置里的名称/密码/安全类型起热点,参数原样、带 & 的也没被拆(V73)" \
        "grep -qx '|wifi|start-softap|MyTab&1|wpa3|pass&word1|-b|any' '$T/cur_$mode.hs.args' && grep -q '^ok wifi start-softap' '$T/cur_$mode.hs.txt'"
    check "hotspot status:on 时有 frequency/bandwidth/bandwidth_mhz/band(等号后带空格的真实格式);关着时 hotspot=off(V74)" \
        "grep -q '^hotspot=on' '$T/cur_$mode.hs.txt' && grep -q '^frequency=5180' '$T/cur_$mode.hs.txt' && grep -q '^bandwidth=4' '$T/cur_$mode.hs.txt' && grep -q '^bandwidth_mhz=80' '$T/cur_$mode.hs.txt' && grep -q '^band=5G' '$T/cur_$mode.hs.txt' && grep -q '^hotspot=off' '$T/cur_$mode.hs.txt' && ! grep -q 'err hotspot_status' '$T/cur_$mode.hs.txt'"
    check "rexec:没打开时拒绝;打开后能读普通文件、拒绝敏感路径/非白名单/元字符;off 后又拒绝(V73)" \
        "awk '/^## heraldctl rexec cat .*rx.txt\$/{n++} END{exit n!=3}' '$T/cur_$mode.rx.txt' && grep -q 'err rexec 没打开' '$T/cur_$mode.rx.txt' && grep -q '^hello rexec' '$T/cur_$mode.rx.txt' && grep -q 'err rexec 拒绝: 参数里有敏感路径' '$T/cur_$mode.rx.txt' && grep -q 'err rexec 拒绝: 不在白名单: rm' '$T/cur_$mode.rx.txt' && grep -q 'err rexec 命令行里有 shell 元字符' '$T/cur_$mode.rx.txt' && ! grep -q '^secret' '$T/cur_$mode.rx.txt' && [ -f '$T/cur_$mode/data/local/rx.txt' ]"
    check "rexec 大输出:不经变量和 printf 参数,256KB 截断提示在,前面的行完整(V75)" \
        "[ \$(wc -c < '$T/cur_$mode.big.txt') -gt 250000 ] && grep -qx 'line 1' '$T/cur_$mode.big.txt' && grep -q '已截断' '$T/cur_$mode.big.txt' && ! grep -q 'Argument list too long' '$T/cur_$mode.big.txt'"
    check "spoof patch <日期> all:连 os/vendor/boot_patchlevel 一起改;不带 all 时三项不动(V74)" \
        "grep -q 'patchlevel 也已改为\|patchlevel.*2025-05-05' '$T/cur_$mode.pa.txt' && grep -q 'os_patchlevel = \"2025-05-05\"' '$T/cur_$mode/data/misc/keystore/herald/config.toml' && grep -q 'boot_patchlevel = \"2025-05-05\"' '$T/cur_$mode/data/misc/keystore/herald/config.toml'"
    if [[ -n $BASE_START ]]; then
        run_one base_$mode "$BASE_START" "$BASE_CTL" "$NAVDIR" $mode "$T/base_$mode.txt" || { FAIL=1; continue; }
        # 旧版的 navbar status 是内置的;当前版是插件,回包应相同。heraldctl help 不比较。
        # 唯一允许的差别:旧版在 keymint 输出末尾没有换行时,把 HERALD_GLOBAL_PIF_FLAG= 粘在 JSON 后面(已修的 bug);
        # 比较前把旧版的这种粘连拆开。
        check "和旧版(--baseline)的全部命令回包逐字节相同(旧版 FLAG 粘连的 bug 除外)" \
            "diff <(sed -e 's#$T/[a-z_]*#<F>#g' -e 's/}HERALD_GLOBAL_PIF_FLAG=/}\\nHERALD_GLOBAL_PIF_FLAG=/' -e 's#\\\\/#/#g' '$T/base_$mode.txt') <(sed 's#$T/[a-z_]*#<F>#g' '$T/cur_$mode.txt') >/dev/null"
    fi
done
echo; if (( FAIL )); then echo "协议回归测试:失败"; exit 1; else echo "协议回归测试:全部通过"; fi
