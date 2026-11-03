# zuicamera/camera-id-check:修联想相机在"没有 2 号相机"的系统上一打开就闪退(unknown device 2)。
# 相机应用按机型写死了相机编号(APK 里的 res/Wi.json,TB321FU:后摄 0,2,back_wide=2);启动时 checkIds() 会把系统里
# 不存在的编号作废,但漏了 back_wide / back_tele。这里给 checkIds 补上这两项(smali 补丁),APK 重新签名。
# 有 2 号相机的系统上行为和原版一样(编号存在就保留),所以不影响以后 HAL 暴露广角的情况。
need_input APKTOOL_JAR
for t in java zipalign apksigner python3 openssl unzip; do need_tool "$t"; done
APK=priv-app/ZuiCamera/ZuiCamera.apk
need_file "$APK"
T=$(mktemp -d -p "$WORK")
sudo cat "$SYS/$APK" > "$T/in.apk"
APKTOOL_JAR=$APKTOOL_JAR "$TOOLKIT/lib/apk-smali.sh" "$T/in.apk" "$T/out.apk" python3 -I "$MOD/files/patch_checkids.py" \
    || die "ZuiCamera 打补丁失败"
put "$T/out.apk" "$APK" 0644 0:0 u:object_r:system_file:s0
rm -rf "$T"
log "ZuiCamera checkIds 已补上 back_wide/back_tele 的核对,APK 已重签"
