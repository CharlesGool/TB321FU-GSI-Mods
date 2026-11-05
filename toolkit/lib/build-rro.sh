#!/usr/bin/env bash
# 编一个 RRO(资源覆盖包)APK:aapt2 编译 + 链接 → zipalign → apksigner。
#
# 用法: build-rro.sh <源码目录> <输出.apk> [版本号]
#   源码目录里要有 AndroidManifest.xml 和 res/。版本号默认 1。
#   签名 key 在 $RRO_KEY_DIR(默认仓库 private/overlay-key/ 里的 overlay.pk8 + overlay.x509.pem);没有就现生成一把自签的。
#   预装在 /product/overlay 的 RRO 不检查签名,key 随便哪把都行,所以这把 key 不进仓库。
# 需要: aapt2 zipalign apksigner openssl。
set -euo pipefail
SRC=$(realpath "$1"); OUT=$(realpath -m "$2"); VER=${3:-1}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
KEYDIR=${RRO_KEY_DIR:-$REPO/private/overlay-key}
FW=${RRO_FRAMEWORK_RES:-/usr/share/android-framework-res/framework-res.apk}   # 只用来解析清单里的 android: 属性
if [[ ! -f $FW ]]; then
    # 没装 Debian 的 android-framework-res 包(android 容器里就没有)时,退到 SDK 自带的 android.jar:
    # aapt2 link -I 只拿它解析 android: 属性,任何 API 级别的都够用。取最新的一个;RRO_FRAMEWORK_RES 仍然优先。
    for _j in $(ls -d "${ANDROID_HOME:-/nonexistent}"/platforms/android-*/android.jar /opt/android/sdk/platforms/android-*/android.jar 2>/dev/null | sort -V); do FW=$_j; done
fi
[[ -f $FW ]] || { echo "build-rro: 找不到 framework-res / android.jar(装 android-framework-res,或设 RRO_FRAMEWORK_RES)"; exit 1; }
[[ -f $SRC/AndroidManifest.xml && -d $SRC/res ]] || { echo "build-rro: $SRC 缺 AndroidManifest.xml 或 res/"; exit 1; }
if [[ ! -f $KEYDIR/overlay.pk8 || ! -f $KEYDIR/overlay.x509.pem ]]; then
    mkdir -p "$KEYDIR"
    openssl req -x509 -newkey rsa:2048 -nodes -days 10000 -subj "/CN=herald-overlay" \
        -keyout "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.x509.pem" 2>/dev/null
    openssl pkcs8 -topk8 -nocrypt -inform PEM -outform DER -in "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.pk8"
    rm -f "$KEYDIR/overlay.key.pem"
    echo "build-rro: 生成了新的自签 key: $KEYDIR"
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/c"
aapt2 compile --dir "$SRC/res" -o "$T/c/res.zip"
aapt2 link -o "$T/unsigned.apk" --manifest "$SRC/AndroidManifest.xml" -I "$FW" \
    --min-sdk-version 35 --target-sdk-version 35 --version-code "$VER" --version-name "$VER.0" \
    --package-id 0x7f --allow-reserved-package-id --no-resource-removal "$T/c/res.zip"
zipalign -f -p 4 "$T/unsigned.apk" "$T/aligned.apk"
mkdir -p "$(dirname "$OUT")"
apksigner sign --key "$KEYDIR/overlay.pk8" --cert "$KEYDIR/overlay.x509.pem" --out "$OUT" "$T/aligned.apk"
rm -f "$OUT.idsig"
apksigner verify "$OUT"
# V69 的教训:只含 array(以及 plurals / style 这类复杂资源)的静态 overlay 在设备上 STATE_NO_IDMAP,会拖垮所有应用进程。
# 至少要有一个标量资源(bool / integer / dimen / string…)。
if ! aapt2 dump resources "$OUT" | grep -E '^[[:space:]]+type ' | grep -qvE 'type (array|plurals|style|attr) '; then
    echo "build-rro: $OUT 只含 array/plurals/style 资源,真机上会 NO_IDMAP;加一个标量资源(见 patches/required/general/brightness/README.md「一条硬规则」)"; rm -f "$OUT"; exit 1
fi
echo "build-rro: $OUT"
