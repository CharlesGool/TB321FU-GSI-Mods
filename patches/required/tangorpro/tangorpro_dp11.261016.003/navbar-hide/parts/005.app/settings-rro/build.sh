#!/usr/bin/env bash
# 编 Settings 的 RRO(齿轮页加"隐藏导航栏"入口)。overlay xml 要引用 Settings 的私有资源 / 属性,
# 所以先按真 SettingsGoogle 的资源 ID 生成一个"链接用桩包"(build-stub.py,资源都声明成 public),overlay 链接它;
# 本包 id 0x7e(0x7f 被桩包占了),min-sdk 34(不让 aapt2 把 xml 拆成按 API 版本的两份)。
#   build.sh <SettingsGoogle.apk> <apktool 解出的 Settings res/values/attrs.xml> <输出 apk>
# 签名用 toolkit/lib/build-rro.sh 同一把 overlay key(预装 RRO 不查签名)。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$HERE; while [[ $REPO != / && ! -f $REPO/toolkit/lib/build-rro.sh ]]; do REPO=$(dirname "$REPO"); done   # 往上找仓库根
SET=$(realpath "$1"); ATTRS=$(realpath "$2"); OUT=$(realpath -m "$3")
JAR=${ANDROID_JAR_RRO:-/opt/android/sdk/platforms/android-35/android.jar}
KEYDIR=${RRO_KEY_DIR:-$REPO/private/overlay-key}
[[ -f $KEYDIR/overlay.pk8 ]] || { echo "缺 $KEYDIR/overlay.pk8(先跑一次 toolkit/lib/build-rro.sh 生成)"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
aapt2 dump resources "$SET" > "$W/dump.txt"
python3 -I "$HERE/build-stub.py" "$W/dump.txt" "$ATTRS" "$HERE/res" "$W/stub"
aapt2 compile --dir "$W/stub/res" -o "$W/stub.zip"
aapt2 link -o "$W/stub.apk" --manifest "$W/stub/AndroidManifest.xml" -I "$JAR" "$W/stub.zip"
aapt2 compile --dir "$HERE/res" -o "$W/res.zip"
aapt2 link -o "$W/ov.apk" --manifest "$HERE/AndroidManifest.xml" -I "$JAR" -I "$W/stub.apk" \
    --package-id 0x7e --allow-reserved-package-id --min-sdk-version 34 --target-sdk-version 35 \
    --version-code 1 "$W/res.zip"
zipalign -f -p 4 "$W/ov.apk" "$W/al.apk"
apksigner sign --key "$KEYDIR/overlay.pk8" --cert "$KEYDIR/overlay.x509.pem" --out "$OUT" "$W/al.apk"
sha256sum "$OUT"
