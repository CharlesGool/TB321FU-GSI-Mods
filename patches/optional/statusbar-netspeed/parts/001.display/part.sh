#!/usr/bin/env bash
# statusbar-netspeed/display:状态栏网速显示(原理和取舍见 README.md)。
#   1. 编 HeraldNetSpeed / HeraldNetSpeedFormat → dex(只用公开 API + 反射,classpath 用 SDK 的 android.jar)。
#   2. framework.jar:新加一份 dex,在 Instrumentation.callApplicationOnCreate 开头插一处调用。
# SystemUI 的 APK 不动(平台签名我们没有私钥),所以不涉及任何重新签名。
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
(cd "$WORK/cls" && "$JH/bin/jar" cf "$WORK/netspeed.jar" .)
java -cp "$R8_JAR" com.android.tools.r8.D8 --release --min-api 35 --lib "$ANDROID_JAR" \
    --output "$WORK/dex" "$WORK/netspeed.jar" || die "d8 失败"
[[ -s $WORK/dex/classes.dex ]] || die "dex 没编出来"

# ---- 2. 反编译 framework.jar,插调用 ----
sudo cat "$SYS/framework/framework.jar" > "$WORK/framework.orig.jar"
APK d -f -r -o "$WORK/fw" "$WORK/framework.orig.jar" >/dev/null || die "apktool 反编译 framework.jar 失败"
grep -rqF 'Lcom/android/internal/util/HeraldNetSpeed;' "$WORK/fw"/smali*/com/android/internal/util/ 2>/dev/null \
    && die "framework.jar 里已经有 HeraldNetSpeed 类(底包或别的模块带了同名类)"
python3 -I "$MOD/patch_framework.py" "$WORK/fw" > "$WORK/patch.out" || { cat "$WORK/patch.out"; die "framework.jar 插调用失败(底包和预期不同,见 README)"; }
sed 's/^/    /' "$WORK/patch.out" | head -1
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

# ---- 3. 校验:产物再反编译,改过的 smali 与补丁后等价;新类在 ----
APK d -f -r -o "$WORK/fwcheck" "$WORK/framework.jar" >/dev/null || die "产物 framework.jar 反编译失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/fw" "$WORK/fwcheck" "${CHANGED[@]}"
for c in HeraldNetSpeed 'HeraldNetSpeed$Controller' HeraldNetSpeedFormat; do
    ls "$WORK/fwcheck"/smali*/com/android/internal/util/"$c".smali >/dev/null 2>&1 || die "产物里没有类 $c"
done
grep -qF 'HeraldNetSpeed;->onApplicationCreate' "$WORK/fwcheck"/smali*/android/app/Instrumentation.smali \
    || die "产物里 Instrumentation 的钩子调用没有"

replace "$WORK/framework.jar" framework/framework.jar
mark_modified framework/framework.jar    # 告诉 stale-boot-image:boot image 过期了
log "完成:framework.jar $(sha256sum "$WORK/framework.jar" | cut -c1-16)(+$NEWDEX)"
