# zuicamera/memory-check:修联想相机拍照前的"内存已满"误判(A17 上每次都判满,快门没反应),原理见 README.md。
need_input APKTOOL_JAR
for t in java zipalign apksigner python3 openssl unzip; do need_tool "$t"; done
APK=priv-app/ZuiCamera/ZuiCamera.apk
need_file "$APK"
T=$(mktemp -d -p "$WORK")
sudo cat "$SYS/$APK" > "$T/in.apk"
APKTOOL_JAR=$APKTOOL_JAR "$TOOLKIT/lib/apk-smali.sh" "$T/in.apk" "$T/out.apk" python3 -I "$MOD/files/patch_memory_check.py" \
    || die "ZuiCamera 打补丁失败"
put "$T/out.apk" "$APK" 0644 0:0 u:object_r:system_file:s0
rm -rf "$T"
log "ZuiCamera 内存检查改按真实已用量算,APK 已重签"
