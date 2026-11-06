#!/usr/bin/env bash
# build-consistency-dialog-fix:
#   从底包现取 framework.jar → 反编译 → 把 android.os.Build.isBuildConsistent() 改成 return true
#   → 回编换 dex → 换回树里。去掉开机"设备内部出现了问题"弹窗。
# 只改 framework.jar 里 Build 所在的那一份 dex;不删预编译 boot image(那是 stale-boot-image)。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

# ---- 前提 ----
need_input APKTOOL_JAR
need_tool java
need_tool zipalign
need_file framework/framework.jar
# 必须排在 stale-boot-image 前面(那个模块要等所有改 jar 的模块跑完再清预编译产物)
! mod_ran required/general/boot-kernel/stale-boot-image \
    || die "stale-boot-image 已经跑过了,请把它排在本模块后面(MODS 顺序)"

APK() { java -jar "$APKTOOL_JAR" "$@"; }

sudo cat "$SYS/framework/framework.jar" > "$WORK/framework.orig.jar"
APK d -f -r -o "$WORK/fw" "$WORK/framework.orig.jar" >/dev/null || die "apktool 反编译 framework.jar 失败"

BUILD_SMALI=$(cd "$WORK/fw" && grep -rl 'isBuildConsistent()Z' smali*/android/os/Build.smali 2>/dev/null || true)
if [[ -z $BUILD_SMALI ]]; then
    # A17 QPR(DP11)起 framework.jar 的 classes.dex 是 DEX 041 容器,Build 在后面的段里,apktool 只看得到第一段,所以找不到。
    # framework.jar 在 bootclasspath 上:整包重 dex 会丢 hiddenapi 标志、让预编译 boot image 全部失效,不改它。
    # 改调用方:弹窗唯一的入口是 services.jar 里 ActivityTaskManagerService$LocalService.showSystemReadyErrorDialogsIfNeeded()
    # 调 Build.isBuildConsistent() 的那一处,把结果换成常量 true。services.jar 不在 bootclasspath,拆开重 dex 无副作用
    # (smooth-display / faceunlock 同样这么改)。用户 2026-11-06 test-v1.2 实测 DP11 开机仍有版本不一致弹窗。
    log "framework.jar 里看不到 Build.isBuildConsistent(DEX 041 容器),改 services.jar 里弹窗的调用方"
    source "$MOD/patch_services_caller.sh"
    return 0
fi
grep -q 'TB321FU: 短路跳过' "$WORK/fw/$BUILD_SMALI" && die "Build.smali 里已经有补丁标记,底包可能已打过"
python3 -I "$MOD/patch_build_consistent.py" "$WORK/fw" | sed 's/^/    /'
grep -q 'TB321FU: 短路跳过' "$WORK/fw/$BUILD_SMALI" || die "补丁没落到 $BUILD_SMALI"
# smali 目录名映射到 dex:smali -> classes.dex,smali_classesN -> classesN.dex。只换 Build 所在的那份。
SWAPDEX=$(echo "${BUILD_SMALI%%/*}" | sed 's|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|')
log "Build 在 $SWAPDEX,只换这一份 dex"

APK b -f "$WORK/fw" -o "$WORK/fw_rebuilt.jar" >/dev/null || die "apktool 回编 framework.jar 失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble \
    "$WORK/framework.orig.jar" "$WORK/fw_rebuilt.jar" "$WORK/framework.jar" --swap "$SWAPDEX"

# 校验:产物再反编译,isBuildConsistent 不再调 VintfObject.verifyBuildAtBoot、直接 return 1。
# (回编后 smali 注释会丢,所以不能靠补丁里的注释标记,按语义核对。)
APK d -f -r -o "$WORK/fwcheck" "$WORK/framework.jar" >/dev/null || die "产物 framework.jar 反编译失败"
python3 -I - "$WORK/fwcheck/$BUILD_SMALI" <<'PY' || die "回编后的 framework.jar 的 isBuildConsistent 不是直接 return true"
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'\.method [^\n]*isBuildConsistent\(\)Z\n(.*?)\n\.end method', s, re.S)
body = m.group(1) if m else ""
ok = m and 'verifyBuildAtBoot' not in body and re.search(r'const/4 v0, 0x1\s*\n\s*return v0', body)
sys.exit(0 if ok else 1)
PY
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/fw" "$WORK/fwcheck" "$BUILD_SMALI"
replace "$WORK/framework.jar" framework/framework.jar
mark_modified framework/framework.jar    # 告诉 stale-boot-image:boot image 和 services oat 过期了
log "framework.jar 打补丁完成:$(sha256sum "$WORK/framework.jar" | cut -c1-16)(isBuildConsistent -> true)"
