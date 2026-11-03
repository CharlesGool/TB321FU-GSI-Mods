# zuicamera/app:把原厂 ZUI 相机(com.zui.camera)装成 system/priv-app,配上权限白名单、sysconfig 和 feature 声明。
# 全部从原厂 system 镜像(STOCK_SYSTEM_IMG)现取,仓库里不放 APK。不改相机服务(cameraserver / libcameraservice 不动)。
PKG=com.zui.camera

# ---- 前提 ----
need_input STOCK_SYSTEM_IMG
need_tool aapt
need_file priv-app
need_file etc/permissions
need_file etc/sysconfig
if sudo test -e "$SYS/priv-app/ZuiCamera"; then die "底包里已经有 system/priv-app/ZuiCamera,不重复装"; fi

# 要从原厂 system 取的文件(相对原厂镜像里的 system/)
APK=priv-app/ZuiCamera/ZuiCamera.apk
XMLS=(etc/permissions/privapp-permissions-$PKG.xml
      etc/permissions/$PKG.record.inter.connection.xml
      etc/sysconfig/initial-stopped-states-$PKG.xml)

# ---- 1. 从原厂镜像拷出来(拷完立刻卸载,后面只用 $WORK 里的副本)----
m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_SYSTEM_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 system 镜像 $STOCK_SYSTEM_IMG"; }
miss=
for f in "$APK" "${XMLS[@]}"; do sudo test -f "$m/system/$f" || miss="$miss $f"; done
if [[ -n $miss ]]; then sudo umount "$m"; rmdir "$m"; die "原厂 system 镜像里没有:$miss(固件换了?核对文件名)"; fi
mkdir -p "$WORK/stock"
for f in "$APK" "${XMLS[@]}"; do sudo cat "$m/system/$f" > "$WORK/stock/$(basename "$f")"; done
sudo umount "$m"; rmdir "$m"

# ---- 2. 核对 APK ----
pkg=$(aapt dump badging "$WORK/stock/ZuiCamera.apk" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*versionName='\([^']*\)'.*/\1 \2/p")
if [[ ${pkg%% *} != "$PKG" ]]; then die "取到的 ZuiCamera.apk 包名不是 $PKG:${pkg:-读不出}"; fi
log "原厂 ZuiCamera ${pkg#* }"
min=$(aapt dump badging "$WORK/stock/ZuiCamera.apk" 2>/dev/null | sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p")
sdk=$(sudo sed -n 's/^ro.build.version.sdk=//p' "$SYS/build.prop" | head -1)
if [[ -n $min && -n $sdk ]] && (( min > sdk )); then die "ZuiCamera 要求 SDK $min,底包是 SDK $sdk"; fi

# ---- 3. 放进镜像(priv-app 目录自己建并定标签,不然是 unlabeled)----
put_dir priv-app/ZuiCamera 0755 0:0 u:object_r:system_file:s0
put "$WORK/stock/ZuiCamera.apk" priv-app/ZuiCamera/ZuiCamera.apk 0644 0:0 u:object_r:system_file:s0
for f in "${XMLS[@]}"; do put "$WORK/stock/$(basename "$f")" "$f" 0644 0:0 u:object_r:system_file:s0; done

# ---- 4. 默认授权 ----
# 联想相机启动时检查 CAMERA、RECORD_AUDIO、READ/WRITE_EXTERNAL_STORAGE、READ_MEDIA_IMAGES,缺一项就弹"缺少运行所需的必要权限"。
# 它 target SDK 34,READ/WRITE_EXTERNAL_STORAGE 在设置里没有开关,用户没法自己授予(2026-11-01 V102 真机:只缺这两项,adb 授权后正常)。
# 原厂系统里没有 default-permissions 文件,这里补一份。位置权限不默认授予(相机自己会问)。
sudo test -d "$SYS/etc/default-permissions" || put_dir etc/default-permissions 0755 0:0 u:object_r:system_file:s0   # GSI 底包里没有这个目录
cat > "$WORK/default-permissions-$PKG.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<!-- TB321FU-GSI:联想相机启动时检查的必要权限,开机默认授予 -->
<exceptions>
    <exception package="$PKG">
        <permission name="android.permission.CAMERA" fixed="false"/>
        <permission name="android.permission.RECORD_AUDIO" fixed="false"/>
        <permission name="android.permission.READ_EXTERNAL_STORAGE" fixed="false"/>
        <permission name="android.permission.WRITE_EXTERNAL_STORAGE" fixed="false"/>
        <permission name="android.permission.READ_MEDIA_IMAGES" fixed="false"/>
    </exception>
</exceptions>
XML
put "$WORK/default-permissions-$PKG.xml" etc/default-permissions/default-permissions-$PKG.xml 0644 0:0 u:object_r:system_file:s0
log "完成:ZuiCamera priv-app + 权限白名单 + sysconfig + feature + 默认授权"
