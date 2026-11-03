# 版本号:ro.build.display.id = $DISPLAY_ID(设置里"版本号"显示的就是它)。
need_file build.prop
: "${DISPLAY_ID:?}"
prop build.prop ro.build.display.id "$DISPLAY_ID"
# 另写一个不会被 herald 全局伪装(resetprop ro.build.*)盖掉的版本标记,用来确认刷的是哪一版
: "${VERSION:?}"
prop build.prop ro.tb321fu.mod_version "${IMAGE_NAME:-$VERSION}" --add
sudo grep -qxF "ro.build.display.id=$DISPLAY_ID" "$SYS/build.prop" || die "display.id 没改成功"
log "完成: $DISPLAY_ID"
