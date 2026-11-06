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

# 每一版都让 PackageManager 认成"系统升级"。PM 只在 PackagePartitions.FINGERPRINT
# (ro.build.fingerprint + ro.{system,vendor,odm,oem,product,system_ext}.build.fingerprint 的摘要)变了时
# 才按升级处理:重新推算系统应用的 ABI、重给默认权限、作废包解析缓存。我们各版的指纹都沿用底包的,
# 保留数据刷新版时 PM 只当普通重启,沿用 /data/system/packages.xml 里旧版的记录。
# DP11 user-v1.1 真机:WebView 从"占位+压缩包"换成完整 APK,保留数据刷入后 PM 沿用占位包的 ABI(空),
# 加载不了 libwebviewchromium.so;把同一个 APK 当更新装一遍才正常。
# 只改 system_ext 的指纹(incremental 后面加本版标记):Play/PIF 看的 ro.build.fingerprint、
# isBuildConsistent() 比对的 ro.system/ro.vendor 指纹都不动。
f=system_ext/etc/build.prop
fp=$(sudo grep -m1 '^ro\.system_ext\.build\.fingerprint=' "$SYS/$f" 2>/dev/null | cut -d= -f2-)
if [[ $fp == *:*:* ]]; then
    tag=$(printf %s "${IMAGE_NAME:-$VERSION}" | sha1sum | cut -c1-8)
    new=${fp%:*}.$tag:${fp##*:}             # .../<incremental>.<tag>:user/release-keys
    # system/build.prop 里也可能有这个键(build-fingerprint 部分 --add-missing 补的),有就一起改
    for g in "$f" build.prop; do
        sudo grep -q '^ro\.system_ext\.build\.fingerprint=' "$SYS/$g" || continue
        prop "$g" ro.system_ext.build.fingerprint "$new"
        sudo grep -qxF "ro.system_ext.build.fingerprint=$new" "$SYS/$g" || die "$g 的 system_ext 指纹没改成功"
    done
    log "system_ext 指纹加本版标记 .$tag(保留数据刷机时触发 PM 升级扫描)"
else
    warn "$f 里没有 ro.system_ext.build.fingerprint,跳过本版标记(保留数据刷机不会触发 PM 升级扫描)"
fi
log "完成: $DISPLAY_ID"
