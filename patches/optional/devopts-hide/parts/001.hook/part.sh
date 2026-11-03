#!/usr/bin/env bash
# devopts-hide/hook:按 App 隐藏开发者选项 / ADB 状态(原理和取舍见 README.md)。
#   1. 编 SettingsCompatHelper → dex(只用公开 API,classpath 用 SDK 的 android.jar)。
#   2. framework.jar:新加一份 dex,在 ZygoteInit.main、Instrumentation.newApplication 两个重载、
#      Settings$NameValueCache.getStringForUser 开头各插一处调用。
#   3. SELinux:配置文件的类型 + 只给 zygote 读。
# 规则文件由 devopts-hide/control 写;没有规则文件时钩子什么都不做,整机行为和没装一样。
# 改了 framework.jar,必须排在 stale-boot-image 前面。

need_input APKTOOL_JAR
need_input R8_JAR
need_input ANDROID_JAR
need_tool java
need_tool zipalign
need_file framework/framework.jar
! mod_ran required/general/boot-kernel/stale-boot-image \
    || die "stale-boot-image 已经跑过了,请把本模块排在它前面(MODS 顺序)"

JH=${FU_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
APK() { java -jar "$APKTOOL_JAR" "$@"; }

# ---- 1. 编类 → dex ----
rm -rf "$WORK/cls" "$WORK/dex"; mkdir -p "$WORK/cls" "$WORK/dex"
"$JH/bin/javac" -nowarn -encoding UTF-8 --release 17 -proc:none -cp "$ANDROID_JAR" -d "$WORK/cls" \
    $(find "$MOD/src/java" -name '*.java') || die "javac 失败"
(cd "$WORK/cls" && "$JH/bin/jar" cf "$WORK/devhide.jar" .)
java -cp "$R8_JAR" com.android.tools.r8.D8 --release --min-api 35 --lib "$ANDROID_JAR" \
    --output "$WORK/dex" "$WORK/devhide.jar" || die "d8 失败"
[[ -s $WORK/dex/classes.dex ]] || die "dex 没编出来"

# ---- 2. 反编译 framework.jar,插调用 ----
sudo cat "$SYS/framework/framework.jar" > "$WORK/framework.orig.jar"
APK d -f -r -o "$WORK/fw" "$WORK/framework.orig.jar" >/dev/null || die "apktool 反编译 framework.jar 失败"
grep -rqF 'Lcom/android/internal/os/SettingsCompatHelper;' "$WORK/fw"/smali*/com/android/internal/os/ 2>/dev/null \
    && die "framework.jar 里已经有 SettingsCompatHelper 类(底包或别的模块带了同名类)"
python3 -I "$MOD/patch_framework.py" "$WORK/fw" > "$WORK/patch.out" || { cat "$WORK/patch.out"; die "framework.jar 插调用失败(底包和预期不同,见 README)"; }
sed 's/^/    /' "$WORK/patch.out" | head -4
read -r -a CHANGED <<< "$(tail -1 "$WORK/patch.out")"
[[ ${#CHANGED[@]} -ge 1 ]] || die "没算出被改的 smali"

mapfile -t SWAP < <(printf '%s\n' "${CHANGED[@]}" | sed 's|/.*||; s|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|' | sort -u)
SWAPARGS=(); for d in "${SWAP[@]}"; do SWAPARGS+=(--swap "$d"); done
N=$(unzip -Z1 "$WORK/framework.orig.jar" | grep -c '^classes[0-9]*\.dex$')
NEWDEX=classes$((N + 1)).dex
log "改 ${SWAP[*]},新类放 $NEWDEX"

APK b -f "$WORK/fw" -o "$WORK/fw_rebuilt.jar" >/dev/null || die "apktool 回编 framework.jar 失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble "$WORK/framework.orig.jar" "$WORK/fw_rebuilt.jar" "$WORK/framework.jar" \
    "${SWAPARGS[@]}" --add "$NEWDEX=$WORK/dex/classes.dex"
[[ $(unzip -Z1 "$WORK/framework.jar" | grep -c '^classes[0-9]*\.dex$') -eq $((N + 1)) ]] || die "产物 dex 数量不对"

# ---- 3. 校验:产物再反编译,改过的 smali 与补丁后等价;新类在;四处调用都在 ----
APK d -f -r -o "$WORK/fwcheck" "$WORK/framework.jar" >/dev/null || die "产物 framework.jar 反编译失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/fw" "$WORK/fwcheck" "${CHANGED[@]}"
ls "$WORK/fwcheck"/smali*/com/android/internal/os/SettingsCompatHelper.smali >/dev/null 2>&1 \
    || die "产物里没有 SettingsCompatHelper 类"
_ni=$(grep -c 'SettingsCompatHelper;->' "$WORK/fwcheck"/smali*/android/app/Instrumentation.smali | awk -F: '{s+=$NF} END {print s+0}')
_nz=$(grep -c 'SettingsCompatHelper;->init' "$WORK/fwcheck"/smali*/com/android/internal/os/ZygoteInit.smali | awk -F: '{s+=$NF} END {print s+0}')
_ng=$(grep -c 'SettingsCompatHelper;->over' "$WORK/fwcheck"/smali*/android/provider/Settings\$NameValueCache.smali | awk -F: '{s+=$NF} END {print s+0}')
[[ $_ni -eq 2 && $_nz -eq 1 && $_ng -eq 1 ]] || die "产物里钩子调用数不对(Instrumentation $_ni/2, ZygoteInit $_nz/1, NameValueCache $_ng/1)"

replace "$WORK/framework.jar" framework/framework.jar
mark_modified framework/framework.jar    # 告诉 stale-boot-image:boot image 过期了
fc_append "devopts-hide/hook: 规则文件(restorecon 之后标签也不会丢)" <<'FC'
/data/system/settings_compat\.conf    u:object_r:settings_compat_file:s0
FC
cil_append "devopts-hide/hook" "$MOD/sepolicy.cil"
log "完成:framework.jar $(sha256sum "$WORK/framework.jar" | cut -c1-16)(+$NEWDEX)"
