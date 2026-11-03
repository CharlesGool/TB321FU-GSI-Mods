# zuicamera/real-device-id:全局伪装开着时联想相机也看到真实机型(TB321FU),不再一启动就崩。
# 全局伪装(spoof/global-pif)全局改 ro.product.{brand,device,manufacturer,model,name},Build.DEVICE 变成 tangorpro;
# 相机按 Build.DEVICE 选相机配置和机型分支,匹配不到就崩在 ModeRecyclerView。这里把相机自己代码里读 Build.DEVICE/MODEL/
# BRAND/MANUFACTURER/PRODUCT 的地方改成读 ro.product.vendor.* / ro.product.system.*(全局伪装不改这两组),APK 重签。
# 只影响相机这一个应用;全局伪装关着时读到的值和 Build.* 一样。
need_input APKTOOL_JAR
for t in java zipalign apksigner python3 openssl unzip; do need_tool "$t"; done
APK=priv-app/ZuiCamera/ZuiCamera.apk
need_file "$APK"
T=$(mktemp -d -p "$WORK")
sudo cat "$SYS/$APK" > "$T/in.apk"
APKTOOL_JAR=$APKTOOL_JAR "$TOOLKIT/lib/apk-smali.sh" "$T/in.apk" "$T/out.apk" python3 -I "$MOD/files/patch_real_build.py" \
    || die "ZuiCamera 打补丁失败"
put "$T/out.apk" "$APK" 0644 0:0 u:object_r:system_file:s0
rm -rf "$T"
log "ZuiCamera 读机型改成 ro.product.vendor.*/system.*(全局伪装下仍是真实机型),APK 已重签"
