# pixel-camera:把 Google 相机 4.4(com.google.android.GoogleCamera)装成 system/app。
# APK 由用户提供(PIXEL_CAMERA_APK,见 conf.d/pixel-camera.conf),仓库里不放。原生库(arm64)解出来放在 APK 旁边的 lib/arm64/,
# 系统应用没有安装过程,PackageManager 开机扫描 /system/app 时直接用这个目录里的库。
# 和联想相机(required/general/camera/zuicamera)包名不同,可以同时装;两个相机一起装时桌面有两个相机图标。
PKG=com.google.android.GoogleCamera
need_input PIXEL_CAMERA_APK
need_tool aapt
need_tool unzip
need_file app
if sudo test -e "$SYS/app/GoogleCamera" || sudo test -e "$SYS/../product/priv-app/GoogleCamera" || sudo test -e "$SYS/product/priv-app/GoogleCamera"; then
    die "底包里已经有 GoogleCamera(pixel-leftovers 的 google-camera 清单没跑?),不重复装"
fi

pkg=$(aapt dump badging "$PIXEL_CAMERA_APK" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*versionName='\([^']*\)'.*/\1 \2/p")
[[ ${pkg%% *} == "$PKG" ]] || die "PIXEL_CAMERA_APK 的包名不是 $PKG:${pkg:-读不出}"
log "Google 相机 ${pkg#* }"
min=$(aapt dump badging "$PIXEL_CAMERA_APK" 2>/dev/null | sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p")
sdk=$(sudo sed -n 's/^ro.build.version.sdk=//p' "$SYS/build.prop" | head -1)
if [[ -n $min && -n $sdk ]] && (( min > sdk )); then die "Google 相机要求 SDK $min,底包是 SDK $sdk"; fi
aapt dump badging "$PIXEL_CAMERA_APK" 2>/dev/null | grep -q "^native-code:.*'arm64-v8a'" || die "APK 里没有 arm64-v8a 的原生库,本机是 arm64"

mkdir -p "$WORK/lib"
unzip -o -j -q "$PIXEL_CAMERA_APK" 'lib/arm64-v8a/*.so' -d "$WORK/lib"
n=$(ls "$WORK/lib"/*.so | wc -l)
(( n > 0 )) || die "APK 里 lib/arm64-v8a/ 没有 .so"

put_dir app/GoogleCamera 0755 0:0 u:object_r:system_file:s0
put "$PIXEL_CAMERA_APK" app/GoogleCamera/GoogleCamera.apk 0644 0:0 u:object_r:system_file:s0
put_dir app/GoogleCamera/lib 0755 0:0 u:object_r:system_file:s0
put_dir app/GoogleCamera/lib/arm64 0755 0:0 u:object_r:system_file:s0
for f in "$WORK/lib"/*.so; do
    put "$f" "app/GoogleCamera/lib/arm64/$(basename "$f")" 0644 0:0 u:object_r:system_file:s0
done
# 开机默认授予相机、麦克风、存储(位置不授予,相机自己会问)
sudo test -d "$SYS/etc/default-permissions" || put_dir etc/default-permissions 0755 0:0 u:object_r:system_file:s0   # GSI 底包里没有这个目录
cat > "$WORK/default-permissions-$PKG.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<!-- TB321FU-GSI:Google 相机开机默认授予的权限 -->
<exceptions>
    <exception package="$PKG">
        <permission name="android.permission.CAMERA" fixed="false"/>
        <permission name="android.permission.RECORD_AUDIO" fixed="false"/>
        <permission name="android.permission.READ_EXTERNAL_STORAGE" fixed="false"/>
        <permission name="android.permission.WRITE_EXTERNAL_STORAGE" fixed="false"/>
    </exception>
</exceptions>
XML
put "$WORK/default-permissions-$PKG.xml" etc/default-permissions/default-permissions-$PKG.xml 0644 0:0 u:object_r:system_file:s0
log "完成:Google 相机 ${pkg#* } + $n 个 arm64 库"
