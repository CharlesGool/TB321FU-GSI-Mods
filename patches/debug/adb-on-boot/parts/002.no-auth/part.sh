# 免授权 ADB:ro.adb.secure=0(连电脑不再弹授权框)。不碰 ro.debuggable / ro.secure(root 的事归 herald-rooted-shell)。debug-off 写的 system 和 system_ext 两处 ro.adb.secure 都要改回去。
need_file build.prop
need_file system_ext/etc/build.prop
prop build.prop ro.adb.secure 0 --add
prop system_ext/etc/build.prop ro.adb.secure 0 --add

sudo grep -qxF 'ro.adb.secure=0' "$SYS/build.prop" || die "ro.adb.secure 没改成 0"
sudo grep -qxF 'ro.adb.secure=0' "$SYS/system_ext/etc/build.prop" || die "system_ext 的 ro.adb.secure 没改成 0"
log "完成"
