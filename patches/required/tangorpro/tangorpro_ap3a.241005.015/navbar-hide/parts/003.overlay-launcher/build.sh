#!/bin/bash
# 重编 OmkNavHideLauncher.apk(apktool 工程在 src/,产物写到 files/)。需要 java、zipalign、apksigner 和 apktool 2.12.1+。
set -e
cd "$(dirname "$0")"
APKTOOL=${APKTOOL_JAR:-/tmp/v20pif/apktool-2.12.1.jar}
KEYDIR=${KEYDIR:-../../keys}     # AOSP testkey(公开的;预装 overlay 不检查签名,随便哪把都行)
java -jar "$APKTOOL" b -f -o files/OmkNavHideLauncher.unsigned.apk src >/dev/null
zipalign -f -p 4 files/OmkNavHideLauncher.unsigned.apk files/OmkNavHideLauncher.aligned.apk
apksigner sign --key "$KEYDIR/testkey.pk8" --cert "$KEYDIR/testkey.x509.pem" --out files/OmkNavHideLauncher.apk files/OmkNavHideLauncher.aligned.apk
rm -f files/OmkNavHideLauncher.unsigned.apk files/OmkNavHideLauncher.aligned.apk files/OmkNavHideLauncher.apk.idsig
echo "built files/OmkNavHideLauncher.apk"
