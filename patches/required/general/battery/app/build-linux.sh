#!/usr/bin/env bash
# 在 Linux(android 构建容器)上编 TB321FU-Battery.apk:SDK 自带工具,不用 Gradle、不用库。
#   build-linux.sh [输出 apk] [versionCode] [versionName]
# 签名 key:keystore/tb321fu-battery.jks(密码 tb321fu,不进仓库);以后升级必须用同一把。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-$HERE/out/TB321FU-Battery.apk}")
VC=${2:-2}; VN=${3:-1.1}
SDK=${ANDROID_SDK:-/opt/android/sdk}; BT=$SDK/build-tools/35.0.0; JAR=$SDK/platforms/android-35/android.jar
KS=${BATTERY_KS:-$HERE/keystore/tb321fu-battery.jks}
[[ -f $KS ]] || { echo "缺签名 key $KS"; exit 1; }
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
mkdir -p "$B/gen" "$B/classes" "$B/dex" "$(dirname "$OUT")"
"$BT/aapt2" compile --dir "$HERE/res" -o "$B/res.zip"
"$BT/aapt2" link -o "$B/base.apk" -I "$JAR" --manifest "$HERE/AndroidManifest.xml" --java "$B/gen" \
    --min-sdk-version 34 --target-sdk-version 35 --version-code "$VC" --version-name "$VN" "$B/res.zip"
find "$HERE/src" "$B/gen" -name '*.java' > "$B/sources.txt"
javac -encoding UTF-8 --release 17 -Xlint:-options -Werror -classpath "$JAR" -d "$B/classes" @"$B/sources.txt"
"$BT/d8" --release --min-api 34 --lib "$JAR" --output "$B/dex" $(find "$B/classes" -name '*.class')
cp "$B/base.apk" "$B/unsigned.apk"
python3 -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'a',zipfile.ZIP_STORED); z.write(sys.argv[2],'classes.dex'); z.close()" "$B/unsigned.apk" "$B/dex/classes.dex"
"$BT/zipalign" -f -p 4 "$B/unsigned.apk" "$B/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:tb321fu --key-pass pass:tb321fu --ks-key-alias battery --out "$OUT" "$B/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT" | grep -m1 'SHA-256'
sha256sum "$OUT"
