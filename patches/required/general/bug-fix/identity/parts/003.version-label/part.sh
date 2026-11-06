# 版本号:ro.build.display.id = $DISPLAY_ID(设置里"版本号"显示的就是它)。
# init 按 system → system_ext → vendor → odm → product 的顺序读 build.prop,同名 ro.* 后读的覆盖先读的。
# 新版 MysticGSI 在 product/etc/build.prop 里也写了 ro.build.display.id=Ported.Using.MysticGSI.Tool,
# 只改 system 的话设置里显示的是 product 那份(DP11 test-v1.4 真机实测版本号一直不变)。所以凡是写了这个键的 build.prop 都改。
need_file build.prop
: "${DISPLAY_ID:?}"
prop build.prop ro.build.display.id "$DISPLAY_ID"
for f in system_ext/etc/build.prop product/etc/build.prop; do
    sudo test -f "$SYS/$f" || continue
    if sudo grep -q '^ro\.build\.display\.id=' "$SYS/$f"; then
        prop "$f" ro.build.display.id "$DISPLAY_ID"
        sudo grep -qxF "ro.build.display.id=$DISPLAY_ID" "$SYS/$f" || die "$f 的 display.id 没改成功"
        log "$f 里也有 ro.build.display.id(会覆盖 system 的),一并改了"
    fi
done
# 另写一个不会被 herald 全局伪装(resetprop ro.build.*)盖掉的版本标记,用来确认刷的是哪一版
: "${VERSION:?}"
prop build.prop ro.tb321fu.mod_version "${IMAGE_NAME:-$VERSION}" --add
sudo grep -qxF "ro.build.display.id=$DISPLAY_ID" "$SYS/build.prop" || die "display.id 没改成功"
log "完成: $DISPLAY_ID"
