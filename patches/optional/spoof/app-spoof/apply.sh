#!/usr/bin/env bash
# spoof/app-spoof:按 App 伪装 Build.*(原理和取舍见 README.md)。
#   1. framework.jar:加一份新 dex(ZygoteCompatHelper),在 ZygoteInit.main 和 Instrumentation.newApplication 两个重载开头插调用。
#   2. 默认名单、broker 插件(spoof_mode / spoof_apps)、heraldctl 插件(spoofmode / spoofapps)。
#   3. SELinux:配置文件的类型 + 只给 zygote 读。
# 配置文件由伪装脚本在 post-fs-data 写(按模式分支),这部分改的是 attestation-fix、spoof/global-pif 的文件,
# 补丁在 pending/,合并前本模块只装钩子:没有配置文件时钩子什么都不做,整机行为和没装一样。

need_input APKTOOL_JAR
need_input R8_JAR
need_input ANDROID_JAR
need_tool java
need_tool zipalign
need_file framework/framework.jar
require_mod required/general/attestation-fix
! mod_ran required/general/boot-kernel/stale-boot-image \
    || die "stale-boot-image 已经跑过了,请把本模块排在它前面(MODS 顺序)"

JH=${FU_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
# 构建开关(V89/V90 查 Holmes 用):
#   APP_SPOOF_LAYOUT=newdex(默认,钩子类单独放 classes<N+1>.dex)| merge(并进 ZygoteInit 所在的那份 dex,framework.jar 的 dex 数量不变)
#   APP_SPOOF_HOOKS=1(默认,插三处调用)| 0(只放类、不插调用,钩子永远不会被调到)
LAYOUT=${APP_SPOOF_LAYOUT:-newdex}; HOOKS=${APP_SPOOF_HOOKS:-1}
[[ $LAYOUT == newdex || $LAYOUT == merge ]] || die "APP_SPOOF_LAYOUT 只能是 newdex 或 merge"
[[ $HOOKS == 1 || $HOOKS == 0 ]] || die "APP_SPOOF_HOOKS 只能是 1 或 0"
log "布局 $LAYOUT,插调用 $HOOKS"
APK() { java -jar "$APKTOOL_JAR" "$@"; }

# ---- 1. 编钩子类 → dex(只用公开 API + 反射,classpath 用 SDK 的 android.jar 就够)----
rm -rf "$WORK/cls" "$WORK/dex"; mkdir -p "$WORK/cls" "$WORK/dex"
"$JH/bin/javac" -nowarn -encoding UTF-8 --release 17 -proc:none -cp "$ANDROID_JAR" -d "$WORK/cls" \
    $(find "$MOD/src/java" -name '*.java') || die "javac 失败"
(cd "$WORK/cls" && "$JH/bin/jar" cf "$WORK/hooks.jar" .)
java -cp "$R8_JAR" com.android.tools.r8.D8 --release --min-api 35 --lib "$ANDROID_JAR" \
    --output "$WORK/dex" "$WORK/hooks.jar" || die "d8 失败"
[[ -s $WORK/dex/classes.dex ]] || die "钩子 dex 没编出来"

# ---- 2. 反编译 framework.jar,插调用 ----
sudo cat "$SYS/framework/framework.jar" > "$WORK/framework.orig.jar"
APK d -f -r -o "$WORK/fw" "$WORK/framework.orig.jar" >/dev/null || die "apktool 反编译 framework.jar 失败"
grep -rqF 'Lcom/android/internal/os/ZygoteCompatHelper;' "$WORK/fw"/smali*/com/android/internal/os/ 2>/dev/null \
    && die "framework.jar 里已经有 ZygoteCompatHelper 类,底包可能已经带了同名钩子"
if [[ $HOOKS == 1 ]]; then
    python3 -I "$MOD/patch_framework.py" "$WORK/fw" > "$WORK/patch.out" || { cat "$WORK/patch.out"; die "framework.jar 插调用失败(底包和预期不同,见 README)"; }
    sed 's/^/    /' "$WORK/patch.out" | head -3
    read -r -a CHANGED <<< "$(tail -1 "$WORK/patch.out")"
    [[ ${#CHANGED[@]} -ge 1 ]] || die "没算出被改的 smali"
else
    CHANGED=()
fi
ZI=$(cd "$WORK/fw" && ls smali*/com/android/internal/os/ZygoteInit.smali) || die "找不到 ZygoteInit.smali"
if [[ $LAYOUT == merge ]]; then
    # 钩子 dex → smali,放进 ZygoteInit 所在那份 dex 的同一个包目录;那份 dex 跟着重编
    rm -rf "$WORK/hk"; (cd "$WORK/dex" && rm -f ../hooksdex.jar && zip -q ../hooksdex.jar classes.dex)
    APK d -f -r -o "$WORK/hk" "$WORK/hooksdex.jar" >/dev/null || die "钩子 dex 反编译失败"
    cp "$WORK/hk"/smali/com/android/internal/os/*.smali "$WORK/fw/${ZI%/ZygoteInit.smali}/" || die "钩子 smali 拷不过去"
    for f in "$WORK/hk"/smali/com/android/internal/os/*.smali; do CHANGED+=("${ZI%/ZygoteInit.smali}/$(basename "$f")"); done
fi

# 要换的 dex = 被改的 smali 所在的那几份;newdex 布局时新 dex 排在原有最后一份之后
SWAP=(); if [[ ${#CHANGED[@]} -gt 0 ]]; then mapfile -t SWAP < <(printf '%s\n' "${CHANGED[@]}" | sed 's|/.*||; s|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|' | sort -u); fi
SWAPARGS=(); for d in "${SWAP[@]}"; do SWAPARGS+=(--swap "$d"); done
N=$(unzip -Z1 "$WORK/framework.orig.jar" | grep -c '^classes[0-9]*\.dex$')
ADDARGS=(); NEWDEX=""
if [[ $LAYOUT == newdex ]]; then NEWDEX=classes$((N + 1)).dex; ADDARGS=(--add "$NEWDEX=$WORK/dex/classes.dex"); fi
log "改 ${SWAP[*]:-(无)},新类放 ${NEWDEX:-${ZI%%/*}(并入)}"

if [[ ${#SWAP[@]} -gt 0 ]]; then
    APK b -f "$WORK/fw" -o "$WORK/fw_rebuilt.jar" >/dev/null || die "apktool 回编 framework.jar 失败"
else
    cp "$WORK/framework.orig.jar" "$WORK/fw_rebuilt.jar"
fi
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble "$WORK/framework.orig.jar" "$WORK/fw_rebuilt.jar" "$WORK/framework.jar" \
    "${SWAPARGS[@]}" "${ADDARGS[@]}"
[[ $(unzip -Z1 "$WORK/framework.jar" | grep -c '^classes[0-9]*\.dex$') -eq $((N + ${#ADDARGS[@]} / 2)) ]] || die "产物 dex 数量不对"

# ---- 3. 校验:产物再反编译,改过的 smali 与补丁后等价;新类在 ----
APK d -f -r -o "$WORK/fwcheck" "$WORK/framework.jar" >/dev/null || die "产物 framework.jar 反编译失败"
if [[ ${#CHANGED[@]} -gt 0 ]]; then python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/fw" "$WORK/fwcheck" "${CHANGED[@]}"; fi
ls "$WORK/fwcheck"/smali*/com/android/internal/os/ZygoteCompatHelper.smali >/dev/null 2>&1 \
    || die "产物里没有 ZygoteCompatHelper 类"
_nh=$( { grep -rlF 'ZygoteCompatHelper;->' "$WORK/fwcheck"/smali*/android/app/Instrumentation.smali "$WORK/fwcheck"/smali*/com/android/internal/os/ZygoteInit.smali || true; } | wc -l)
[[ $_nh -eq $((HOOKS * 2)) ]] || die "产物里 Instrumentation / ZygoteInit 的钩子调用数不对($_nh)"

replace "$WORK/framework.jar" framework/framework.jar
mark_modified framework/framework.jar    # 告诉 stale-boot-image:boot image 过期了

# ---- 4. 名单、插件、SELinux ----
put_dir etc/herald_payload/app-spoof 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/targets.default"     etc/herald_payload/app-spoof/targets.default 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/app-spoof.sh"        etc/herald_payload/plugins/app-spoof.sh      0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-app-spoof.sh" etc/heraldctl.d/app-spoof.sh                 0644 0:0 u:object_r:system_file:s0
cil_append "spoof/app-spoof" "$MOD/sepolicy.cil"
log "完成:framework.jar $(sha256sum "$WORK/framework.jar" | cut -c1-16)(布局 $LAYOUT${NEWDEX:+ +$NEWDEX},插调用 $HOOKS)"
