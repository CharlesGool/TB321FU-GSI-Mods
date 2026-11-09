# cover-rotation-fix:services.jar 加 Tb321fuHwPolicy 并挂到 PhoneWindowManager.systemReady() 末尾。
# 流程同 smooth-display:现取 services.jar → 拆 041 → apktool 反编译 → 打钩子 → 回编只换被改的那份 dex,
# helper 单独 javac + d8 成一份新 dex 追加在最后(编号现算,faceunlock 的 classes4.dex 要排在本补丁前面)。
need_input APKTOOL_JAR
need_input ANDROID_JAR
for t in java javac d8 zipalign unzip; do need_tool "$t"; done
need_file framework/services.jar
! mod_ran required/general/boot-kernel/stale-boot-image || die "stale-boot-image 已经跑过了,请把它排在本模块后面(MODS 顺序)"

APK() { java -jar "$APKTOOL_JAR" "$@"; }

# ---- 1. 编 helper → 一份独立 dex(只用公开 API,隐藏 API 走反射)----
mkdir -p "$WORK/helper/classes" "$WORK/helper/dex"
javac --release 17 -Xlint:-options -cp "$ANDROID_JAR" -d "$WORK/helper/classes" \
    "$MOD/src/com/android/server/policy/Tb321fuHwPolicy.java" || die "javac 编 Tb321fuHwPolicy 失败"
mapfile -t CLS < <(find "$WORK/helper/classes" -name '*.class')
d8 --release --min-api 34 --lib "$ANDROID_JAR" --output "$WORK/helper/dex" "${CLS[@]}" || die "d8 失败"
[[ -s $WORK/helper/dex/classes.dex && ! -e $WORK/helper/dex/classes2.dex ]] || die "helper 应该正好编出一份 classes.dex"

# ---- 2. 现取 services.jar,拆 041,反编译,打钩子 ----
sudo cat "$SYS/framework/services.jar" > "$WORK/services.orig.jar"
source "$TOOLKIT/lib/dex041.sh"
undex041_jar "$WORK/services.orig.jar" "$WORK/services.orig.jar"
unzip -Z1 "$WORK/services.orig.jar" | grep -q 'com/android/server/policy/Tb321fuHwPolicy' && die "services.jar 里已经有 Tb321fuHwPolicy"
APK d -f -r -o "$WORK/svc" "$WORK/services.orig.jar" >/dev/null || die "apktool 反编译 services.jar 失败"
! grep -rqs 'Lcom/android/server/policy/Tb321fuHwPolicy;' "$WORK/svc"/smali*/com/android/server/policy/ || die "services.jar 里已经有 Tb321fuHwPolicy"
python3 -I "$MOD/apply_hook.py" "$WORK/svc" | tee "$WORK/hook.log" | sed 's/^/    /'
grep -q '^OK ' "$WORK/hook.log" || die "钩子没打上(PhoneWindowManager.systemReady 和预期不一样)"
CHANGED=$(tail -1 "$WORK/hook.log")
SWAPDEX=$(echo "${CHANGED%%/*}" | sed 's|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|')

# 新 dex 编号 = 现有 dex 个数 + 1(classes.dex 算第 1 份),要求现有编号连续
N=$(unzip -Z1 "$WORK/services.orig.jar" | grep -cE '^classes[0-9]*\.dex$')
for ((i = 2; i <= N; i++)); do unzip -Z1 "$WORK/services.orig.jar" | grep -qx "classes$i.dex" || die "services.jar 的 dex 编号不连续(缺 classes$i.dex)"; done
NEWDEX=classes$((N + 1)).dex
log "钩子在 $SWAPDEX,helper 放进新增的 $NEWDEX"

# ---- 3. 回编,换 dex + 加 helper dex ----
APK b -f "$WORK/svc" -o "$WORK/svc_rebuilt.jar" >/dev/null || die "apktool 回编失败(smali 有错)"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble "$WORK/services.orig.jar" "$WORK/svc_rebuilt.jar" "$WORK/services.jar" \
    --swap "$SWAPDEX" --add "$NEWDEX=$WORK/helper/dex/classes.dex"

# ---- 4. 校验 ----
APK d -f -r -o "$WORK/check" "$WORK/services.jar" >/dev/null || die "产物 jar 反编译失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/svc" "$WORK/check" "$CHANGED"
grep -qF 'Tb321fuHwPolicy;->init(Landroid/content/Context;Ljava/lang/Object;)V' "$WORK/check/$CHANGED" || die "产物里找不到钩子,回编丢了补丁"
H=$(grep -rlF '.class public final Lcom/android/server/policy/Tb321fuHwPolicy;' "$WORK/check"/smali* | wc -l)
[[ $H == 1 ]] || die "产物里 Tb321fuHwPolicy 类有 $H 份,预期 1 份"
grep -rqF '.method public static init(Landroid/content/Context;Ljava/lang/Object;)V' "$WORK/check"/smali*/com/android/server/policy/Tb321fuHwPolicy.smali \
    || die "产物里 Tb321fuHwPolicy.init(Context, Object) 签名不对"

replace "$WORK/services.jar" framework/services.jar
mark_modified framework/services.jar     # 告诉 stale-boot-image:services 的预编译产物过期了
log "完成:services.jar $(sha256sum "$WORK/services.jar" | cut -c1-16)($SWAPDEX 挂钩子 + $NEWDEX helper)"
