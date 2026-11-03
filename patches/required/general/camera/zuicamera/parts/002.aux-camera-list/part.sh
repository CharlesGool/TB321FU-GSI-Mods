# zuicamera/aux-camera-list:把 com.zui.camera 加进 vendor.camera.aux.packagelist,和原厂 build.prop 一致。
# 值从原厂 system 镜像(STOCK_SYSTEM_IMG)的 build.prop 现取,不写死。
KEY=vendor.camera.aux.packagelist
PKG=com.zui.camera

need_input STOCK_SYSTEM_IMG
need_file build.prop

m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_SYSTEM_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 system 镜像 $STOCK_SYSTEM_IMG"; }
val=$(sudo sed -n "s/^$KEY=//p" "$m/system/build.prop" | head -1)
sudo umount "$m"; rmdir "$m"
if [[ -z $val ]]; then die "原厂 system/build.prop 里没有 $KEY"; fi
case ",$val," in *",$PKG,"*) ;; *) die "原厂 $KEY 的值里没有 $PKG:$val";; esac

prop build.prop "$KEY" "$val" --add
if ! sudo grep -qxF "$KEY=$val" "$SYS/build.prop"; then die "system/build.prop 里 $KEY 没写进去"; fi
log "$KEY=$val"

# V72:V71 真机上联想相机闪退 `getCameraCharacteristics: unknown device 2`,shell 里 getprop 读到的是空。
# 这个属性在 vendor_property_contexts 里只被 `vendor.` 前缀标成 vendor_default_prop,GSI 的 cameraserver 没有读它的权限
# (shell 也读不到,所以 getprop 为空不一定表示没设)。两处加固:
#  ① 开机 init 再 setprop 一次(`post-fs-data`,值与 build.prop 相同),不依赖 build.prop 的加载;
#  ② SELinux:允许 cameraserver 和 priv_app 读 vendor_default_prop(只读,只这一类;V72 只放了 cameraserver,真机上被拒的是 priv_app)。
RC=$WORK/tb321fu-camera-aux.rc
{
  echo "# 由 patches/required/general/camera/zuicamera/parts/002.aux-camera-list 生成:联想相机需要的辅助镜头包名清单"
  echo "on post-fs-data"
  echo "    setprop $KEY $val"
} > "$RC"
put "$RC" etc/init/tb321fu-camera-aux.rc 0644 0:0 u:object_r:system_file:s0
cat > "$WORK/camera-aux.cil" <<'CIL'
; zuicamera/aux-camera-list:读 vendor.camera.aux.packagelist(标签 vendor_default_prop)
(allow cameraserver vendor_default_prop (file (read open getattr map)))
; V73:V72 真机日志里是相机应用自己(priv_app)报 `Access denied finding property`——Camera2 客户端在应用进程里读这个属性
(allow priv_app vendor_default_prop (file (read open getattr map)))
CIL
cil_append "zuicamera/aux-camera-list: cameraserver 读 vendor_default_prop" "$WORK/camera-aux.cil"
