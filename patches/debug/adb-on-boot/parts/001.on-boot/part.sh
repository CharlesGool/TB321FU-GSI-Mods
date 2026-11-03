# 开机 ADB 自启动:debug-off 删掉了 Mystic 的 "# Force ADB" 段(含 persist.sys.usb.config),这里把"开机启用 ADB"加回来。
need_file build.prop
prop build.prop persist.sys.usb.config adb,mtp --add
sudo grep -qxF 'persist.sys.usb.config=adb,mtp' "$SYS/build.prop" || die "persist.sys.usb.config 没写进去"
log "完成"
