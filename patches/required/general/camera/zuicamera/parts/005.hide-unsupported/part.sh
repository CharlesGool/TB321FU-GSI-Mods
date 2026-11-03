# zuicamera/hide-unsupported:屏蔽联想相机里依赖本系统没有的组件的功能。
#  - 模式栏去掉"互联录制"(要联想互联服务 com.zui.wifip2p)和"微距"(要 2 号相机,本系统 HAL 不报);
#  - 点"许可协议/隐私政策"(要 com.lenovo.lenovoprivacy)不再闪退。
# 其余依赖外部组件的入口(语音拍照、AI 识图、相册跳转)应用自己会先查对应应用装没装,不用改。
need_input APKTOOL_JAR
for t in java zipalign apksigner python3 openssl unzip; do need_tool "$t"; done
APK=priv-app/ZuiCamera/ZuiCamera.apk
need_file "$APK"
T=$(mktemp -d -p "$WORK")
sudo cat "$SYS/$APK" > "$T/in.apk"
# macro-camera-fix 跑过 = 相机 HAL 按原厂模式报 2 号相机(微距),模式栏保留微距
KEEP=0; mod_ran required/general/hardware-fix/macro-camera-fix && KEEP=1
HIDE_KEEP_MACRO=$KEEP APKTOOL_JAR=$APKTOOL_JAR "$TOOLKIT/lib/apk-smali.sh" "$T/in.apk" "$T/out.apk" python3 -I "$MOD/files/patch_hide.py" \
    || die "ZuiCamera 打补丁失败"
put "$T/out.apk" "$APK" 0644 0:0 u:object_r:system_file:s0
rm -rf "$T"
log "ZuiCamera 已屏蔽互联录制$([[ $KEEP == 1 ]] && echo "(微距保留:macro-camera-fix 开着)" || echo "、微距模式"),隐私/许可链接不再闪退;APK 已重签"
