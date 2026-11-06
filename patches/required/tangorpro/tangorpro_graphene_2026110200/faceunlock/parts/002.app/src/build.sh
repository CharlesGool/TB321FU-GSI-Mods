#!/usr/bin/env bash
# 编 FaceUnlock.apk(com.android.faceunlock, 自签名 priv-app), 不用 AOSP 编译系统.
# 设置入口 overlay(FaceUnlockSettingsOverlay.apk)已拆到 ../../003.settings-entry/src/build.sh, 本脚本不再编它.
#
# 用法: build.sh <底包 system 目录> <输出目录>
# 工具(环境变量, 版本同 ../../001.services-hooks/src/build_dex.sh):
#   JAVA_HOME JDK 17;  D2J dex2jar 2.4.38;  R8 r8-8.5.35.jar;  APKTOOL apktool_2.12.1.jar(给 check_dex.py 用)
#   BT build-tools 35 目录(aapt2 zipalign apksigner);  KOTLIN_HOME kotlinc 2.0.21 目录
#
# 和上游 PixelOS fifteen 分支的区别见 ../README.md(本模块的 README). 要点:
#   - Kotlin 标准库、AIDL stub(vendor.aospa.biometrics.face.*)、vendorImplPrebuilt.jar 都编进 APK 的 dex:
#     应用进程的 classpath 里没有 kotlin-stdlib, 也没有 services.jar
#   - 4 个 Megvii so 不压缩 + 页对齐放在 APK 里, extractNativeLibs=false, 从 APK 直接加载
set -euo pipefail

SYS=$(realpath "$1")
OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
: "${JAVA_HOME:=/usr/lib/jvm/java-17-openjdk-amd64}" "${D2J:?}" "${R8:?}" "${APKTOOL:?}" "${BT:?}" "${KOTLIN_HOME:?}"
UP=$HERE/third_party/ParanoidSense
# AIDL stub 源码和 services.jar 补丁共用一份, 放在 services-hooks 模块里(同组, 路径相对本脚本)
AIDL_SRC=$HERE/../../001.services-hooks/src/java/vendor
KS=${FACEUNLOCK_KEYSTORE:-${KS:-$HERE/faceunlock.keystore}}
[[ -f $UP/res/raw/model_file ]] || { echo "缺上游文件(旷视 SDK/模型), 先跑 ./fetch_upstream.sh" >&2; exit 1; }
if [[ ! -f $KS ]]; then
    echo "==== 生成签名密钥 $KS"
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storetype PKCS12 -alias faceunlock -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass android -keypass android -dname "CN=Face Unlock"
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$OUT" "$T"/{cp,res,gen,kt,aidl,dex,lib/lib/arm64-v8a}

echo "==== classpath"
"$D2J" -f -o "$T/cp/framework.jar" "$SYS/framework/framework.jar" >/dev/null
CP=$T/cp/framework.jar

echo "==== aapt2"
# 旷视模型(res/raw/model_file 等)直接用上游的
for f in $(find "$HERE/app/res" "$UP/res/raw" -type f); do "$BT/aapt2" compile "$f" -o "$T/res/"; done
"$BT/aapt2" link -o "$T/base.apk" --manifest "$HERE/app/AndroidManifest.xml" -I "$SYS/framework/framework-res.apk" \
    --rename-manifest-package com.android.faceunlock --custom-package com.android.faceunlock \
    --java "$T/gen" --min-sdk-version 35 --target-sdk-version 35 "$T"/res/*.flat

echo "==== javac(AIDL stub) + kotlinc"
"$JAVA_HOME/bin/javac" -nowarn -encoding UTF-8 --release 17 -proc:none -cp "$CP" -d "$T/aidl" $(find "$AIDL_SRC" -name '*.java')
"$KOTLIN_HOME/bin/kotlinc" -nowarn -jvm-target 17 -classpath "$CP:$UP/lib/vendorImplPrebuilt.jar:$T/aidl" -d "$T/kt" \
    $(find "$HERE/app/src" -name '*.kt') $(find "$T/gen" -name '*.java')
"$JAVA_HOME/bin/javac" -nowarn -encoding UTF-8 --release 17 -proc:none -cp "$CP" -d "$T/kt" $(find "$T/gen" -name '*.java')
(cd "$T/kt" && "$JAVA_HOME/bin/jar" cf "$T/app.jar" .)
(cd "$T/aidl" && "$JAVA_HOME/bin/jar" cf "$T/aidl.jar" .)

echo "==== d8"
java -cp "$R8" com.android.tools.r8.D8 --release --min-api 35 --lib "$JAVA_HOME" --lib "$CP" --output "$T/dex" \
    "$T/app.jar" "$T/aidl.jar" "$UP/lib/vendorImplPrebuilt.jar" "$KOTLIN_HOME/lib/kotlin-stdlib.jar" 2>&1 \
    | grep -v -E "^Warning: (Expected stack map table|An error occurred when parsing kotlin metadata)" || true

echo "==== 组装 APK"
cp "$T/base.apk" "$T/app.apk"
(cd "$T/dex" && zip -q "$T/app.apk" classes*.dex)
cp "$UP"/lib/lib*.so "$T/lib/lib/arm64-v8a/"
(cd "$T/lib" && zip -q -0 -r "$T/app.apk" lib)
"$BT/zipalign" -f -p 4 "$T/app.apk" "$T/app-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias faceunlock --ks-pass pass:android --key-pass pass:android \
    --out "$OUT/FaceUnlock.apk" "$T/app-aligned.apk"
"$BT/zipalign" -c -p 4 "$OUT/FaceUnlock.apk"
python3 -I - "$OUT/FaceUnlock.apk" <<'EOF'
import sys, zipfile
bad = [i.filename for i in zipfile.ZipFile(sys.argv[1]).infolist()
       if i.filename.endswith('.so') and i.compress_type != zipfile.ZIP_STORED]
sys.exit(f"compressed .so in APK: {bad}") if bad else print("so: stored, page-aligned")
EOF
APKTOOL="$APKTOOL" python3 -I "$HERE/../../001.services-hooks/src/check_dex.py" --boot "$CP" "$OUT/FaceUnlock.apk"

(cd "$OUT" && sha256sum FaceUnlock.apk)
