#!/usr/bin/env bash
# faceunlock/services-hooks:给 services.jar 打人脸解锁用的补丁。
#   1. 从底包现取 services.jar → 反编译 → 打补丁(3 处 Sense 入口 + 57 处 USE_BIOMETRIC_INTERNAL 放行)
#      → 回编换 classes.dex + 塞入现编的 classes4.dex(Sense 框架类)→ 换回树里。
#   2. build.prop 加 ro.face.sense_service=true(SenseHooks / SenseUtils 在 system_server 里读它,所以归本模块)。
# 不放 App、不放 overlay、不放权限 xml(那些在 faceunlock/app、faceunlock/settings-entry)。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

# ---- 前提 ----
for v in APKTOOL_JAR FU_D2J FU_R8 ANDROID_JAR; do need_input "$v"; done
for t in java javac zipalign debugfs unzip; do need_tool "$t"; done
need_file framework/services.jar
need_file framework/framework.jar            # 只当编译 classpath 用,本模块不改它
# 取 core-libart.jar 当 classpath。A17 底包的 ART apex 是压缩格式 .capex(bp1a/ap3a 是 .apex),两种都认。
sudo test -e "$SYS/apex/com.google.android.art.apex" || sudo test -e "$SYS/apex/com.google.android.art.capex" \
    || die "底包里没有 apex/com.google.android.art.{apex,capex},这个模块不适用于当前底包"
need_file build.prop
# services.jar 补丁必须排在 stale-boot-image 前面(那个模块要等所有改 jar 的模块跑完再清预编译产物)
! mod_ran required/general/boot-kernel/stale-boot-image \
    || die "stale-boot-image 已经跑过了,请把它排在本模块后面(MODS 顺序)"

APK() { java -jar "$APKTOOL_JAR" "$@"; }
export JAVA_HOME="${FU_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}" D2J="$FU_D2J" R8="$FU_R8" APKTOOL="$APKTOOL_JAR" ANDROID_JAR="$ANDROID_JAR"

# ---- 1. 现取 services.jar ----
sudo cat "$SYS/framework/services.jar" > "$WORK/services.orig.jar"

# ---- 2. 现编 Sense 框架类 → classes4.dex(classpath 取自当前底包)----
log "编 Sense 框架类(dex2jar 现取 classpath + javac + d8)"
bash "$MOD/src/build_dex.sh" "$SYS" "$WORK/classes4.dex" 2>&1 | sed 's/^/    /'
[[ -s $WORK/classes4.dex ]] || die "classes4.dex 没编出来"

# ---- 3. 反编译 services.jar,打补丁 ----
APK d -f -r -o "$WORK/svc" "$WORK/services.orig.jar" >/dev/null || die "apktool 反编译 services.jar 失败"
# apktool 反编译会刷新所有 smali 的 mtime,所以先打个时间戳,后面只认比它新的文件(= apply_hooks 改过的)
sleep 1; touch "$WORK/.patch_stamp"; sleep 1
# apply_hooks.py 幂等、自带扫描:打完要求残留 USE_BIOMETRIC_INTERNAL 调用点为 0。
python3 -I "$MOD/src/apply_hooks.py" "$WORK/svc" | tee "$WORK/hooks.log" | sed 's/^/    /'
grep -q "剩余 USE_BIOMETRIC_INTERNAL 字符串出现 0 处" "$WORK/hooks.log" \
    || { grep -qE "剩余 USE_BIOMETRIC_INTERNAL 字符串出现 [1-9]" "$WORK/hooks.log" \
         && warn "仍有 USE_BIOMETRIC_INTERNAL 字面值(可能是注解/字符串,非调用点)"; }
grep -qE "FAIL" "$WORK/hooks.log" && die "apply_hooks.py 有 FAIL,补丁没打全(底包的 services.jar 和预期不一样)"
# 入口方法必须命中(换底包/被 R8 改名时在这里失败,而不是出个没功能的包)
for mk in "SenseHooks;->canUseProvider" "SenseHooks;->getProviders" "SenseHooks;->enforceInternal" "SenseHooks;->hasInternal"; do
    grep -rqF -- "$mk" "$WORK/svc"/smali* || die "补丁标记 $mk 没出现在 smali 里,services.jar 和补丁预期不符(见 README 的换底包一节)"
done

# 记下被 apply_hooks.py 改过的 smali(用来回编后做等价核对)
mapfile -t CHANGED < <(cd "$WORK/svc" && find smali* -name '*.smali' -newer "$WORK/.patch_stamp" | sort)
[[ ${#CHANGED[@]} -ge 6 ]] || die "被改的 smali 只有 ${#CHANGED[@]} 个,预期至少 6 个,补丁没打上"
log "apply_hooks 改了 ${#CHANGED[@]} 个 smali:${CHANGED[*]##*/}"

# ---- 4. 回编,只换被补丁改到的那几份 dex + 加 classes4.dex ----
# smali 目录名映射到 dex:smali -> classes.dex,smali_classesN -> classesN.dex。只换真的改过的那份,
# 其余 dex 保持底包原样字节(不然 apktool 回编会把没动的 dex 也改得和底包不一致)。
mapfile -t SWAP < <(printf '%s\n' "${CHANGED[@]}" | sed 's|/.*||; s|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|' | sort -u)
[[ ${#SWAP[@]} -ge 1 ]] || die "算不出要替换的 dex"
SWAPARGS=(); for d in "${SWAP[@]}"; do SWAPARGS+=(--swap "$d"); done
log "被补丁改到的 dex:${SWAP[*]}"
APK b -f "$WORK/svc" -o "$WORK/svc_rebuilt.jar" >/dev/null || die "apktool 回编失败(smali 有错)"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble \
    "$WORK/services.orig.jar" "$WORK/svc_rebuilt.jar" "$WORK/services.jar" \
    "${SWAPARGS[@]}" --add "classes4.dex=$WORK/classes4.dex"

# ---- 5. 校验:产物再反编译一遍,改过的 smali 与补丁后等价 ----
APK d -f -r -o "$WORK/check" "$WORK/services.jar" >/dev/null || die "产物 jar 反编译失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/svc" "$WORK/check" "${CHANGED[@]}"
grep -rqF -- "SenseHooks;->enforceInternal" "$WORK/check"/smali* || die "产物里找不到 SenseHooks 调用,回编丢了补丁"

# ---- 6. 换进树 ----
replace "$WORK/services.jar" framework/services.jar
mark_modified framework/services.jar     # 告诉 stale-boot-image:services 的预编译产物过期了

# ---- 7. ro.face.sense_service=true ----
# 谁读它:system_server 里的 SenseUtils.canUseProvider()(经 SenseHooks.getProviders / canUseProvider),
# 即 classes4.dex 里的代码,所以跟着 services.jar 补丁走。FaceUnlock.apk 不读它(只读可选的 ro.face.sense_service.camera_id)。
if sudo grep -q '^ro.face.sense_service=' "$SYS/build.prop"; then
    log "(build.prop 已有 ro.face.sense_service)"
else
    printf '\n# %s 人脸解锁:让 system_server 注册 SenseProvider\nro.face.sense_service=true\n' "$MOD_NAME" | append build.prop
fi

log "完成:services.jar $(sha256sum "$WORK/services.jar" | cut -c1-16) + ro.face.sense_service"
