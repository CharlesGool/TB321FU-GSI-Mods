# zuicamera/predictive-back:给联想相机(com.zui.camera)开预测性返回。
# 做法:只给二进制 AndroidManifest.xml 的 <application> 加 android:enableOnBackInvokedCallback="true"
#   (resid 0x0101066c,布尔 true),resources.arsc 和 dex 一律不动,再用 overlay key 重签。
# 为什么不用 apktool 整包回编:ZuiCamera 的 styles.xml 用了私有 android 属性,aapt2 重链接会报
#   "resource ... is private" 而失败(apk-smali.sh 也明确不许改 manifest/resources.arsc)。所以直接
#   对二进制 AXML 动刀:在字符串池 index=resmap 长度处插入属性名、resmap 追加该 resid、把 >= 该 index 的
#   字符串引用整体 +1、给 <application> 追加该属性,重算各块大小。真机验证相机内返回(面板/模式/设置页)正常。
# 幂等:manifest 里已有这个属性就原样放回,不重复加。
PKG=com.zui.camera
APK=priv-app/ZuiCamera/ZuiCamera.apk
for t in python3 zipalign apksigner unzip openssl; do need_tool "$t"; done
need_file "$APK"

KEYDIR=${APK_KEY_DIR:-$REPO/private/overlay-key}
if [[ ! -f $KEYDIR/overlay.pk8 || ! -f $KEYDIR/overlay.x509.pem ]]; then
    mkdir -p "$KEYDIR"
    openssl req -x509 -newkey rsa:2048 -nodes -days 10000 -subj "/CN=herald-overlay" \
        -keyout "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.x509.pem" 2>/dev/null
    openssl pkcs8 -topk8 -nocrypt -inform PEM -outform DER -in "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.pk8"
    rm -f "$KEYDIR/overlay.key.pem"
    log "overlay 签名 key 不在,现生成一把自签的($KEYDIR)"
fi

T=$(mktemp -d -p "$WORK")
sudo cat "$SYS/$APK" > "$T/in.apk"

# 1. 取出 + 改 manifest(加预测性返回;已存在则原样)
( cd "$T" && unzip -o -q in.apk AndroidManifest.xml -d orig )
python3 -I "$MOD/files/axml_add_predback.py" "$T/orig/AndroidManifest.xml" "$T/AndroidManifest.new.xml" \
    || die "AXML 加预测性返回失败"

# 2. 只替换 manifest 条目(其余条目/压缩方式原样),保留 resources.arsc 不变
python3 -I - "$T/in.apk" "$T/AndroidManifest.new.xml" "$T/repacked.apk" <<'PY'
import sys, zipfile
src, newman, dst = sys.argv[1], sys.argv[2], sys.argv[3]
man = open(newman, "rb").read()
zin = zipfile.ZipFile(src, "r"); zout = zipfile.ZipFile(dst, "w")
for it in zin.infolist():
    data = man if it.filename == "AndroidManifest.xml" else zin.read(it.filename)
    zi = zipfile.ZipInfo(it.filename, date_time=it.date_time)
    zi.compress_type = it.compress_type; zi.external_attr = it.external_attr
    zi.internal_attr = it.internal_attr; zi.create_system = it.create_system
    zout.writestr(zi, data)
zin.close(); zout.close()
PY

# 3. 对齐 + overlay key 重签
zipalign -f -p 4 "$T/repacked.apk" "$T/aligned.apk"
apksigner sign --key "$KEYDIR/overlay.pk8" --cert "$KEYDIR/overlay.x509.pem" --out "$T/out.apk" "$T/aligned.apk"
apksigner verify "$T/out.apk" >/dev/null || die "签名校验失败"
# 属性是否真写进去,由 axml_add_predback.py 自己重新解析输出校验(上面它退非 0 就已 die),
#   不依赖 aapt2(构建环境里 aapt2 版本/行为不一)。

put "$T/out.apk" "$APK" 0644 0:0 u:object_r:system_file:s0
rm -rf "$T"
log "ZuiCamera 已开预测性返回(manifest enableOnBackInvokedCallback,resources/dex 未改,overlay key 重签)"
