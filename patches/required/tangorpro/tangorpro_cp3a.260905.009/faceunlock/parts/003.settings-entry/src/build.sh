#!/usr/bin/env bash
# 编 FaceUnlockSettingsOverlay.apk(设置里人脸入口的静态 overlay), 不用 AOSP 编译系统.
# 以前和 FaceUnlock.apk 在同一个脚本里编, 现在拆成独立脚本: 不依赖 App 源码, 也不依赖旷视上游文件.
#
# 用法: build.sh <底包 system 目录> <输出目录>
# 工具(环境变量):
#   BT                build-tools 35 目录(aapt2 zipalign apksigner)
#   FACEUNLOCK_KEYSTORE  签名 keystore(alias faceunlock, 口令 android), 不进仓库.
#                        不给就在 src/ 下生成一个新的(overlay 是 static overlay, 靠系统分区加载, 签名换了不影响使用).
# 只用底包的 framework-res.apk 当 link 资源。
set -euo pipefail

SYS=$(realpath "$1")
OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
: "${JAVA_HOME:=/usr/lib/jvm/java-17-openjdk-amd64}" "${BT:?缺 BT(build-tools 35 目录)}"
KS=${FACEUNLOCK_KEYSTORE:-${KS:-$HERE/faceunlock.keystore}}
if [[ ! -f $KS ]]; then
    echo "==== 生成签名密钥 $KS"
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storetype PKCS12 -alias faceunlock -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass android -keypass android -dname "CN=Face Unlock"
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$OUT" "$T/ores"

echo "==== Settings overlay"
for f in $(find "$HERE/overlay/res" -type f); do "$BT/aapt2" compile "$f" -o "$T/ores/"; done
"$BT/aapt2" link -o "$T/overlay.apk" --manifest "$HERE/overlay/AndroidManifest.xml" \
    -I "$SYS/framework/framework-res.apk" --min-sdk-version 35 --target-sdk-version 35 "$T"/ores/*.flat
"$BT/zipalign" -f -p 4 "$T/overlay.apk" "$T/overlay-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias faceunlock --ks-pass pass:android --key-pass pass:android \
    --out "$OUT/FaceUnlockSettingsOverlay.apk" "$T/overlay-aligned.apk"

(cd "$OUT" && sha256sum FaceUnlockSettingsOverlay.apk)
