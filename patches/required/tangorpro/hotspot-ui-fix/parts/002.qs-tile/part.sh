# 快捷设置里显示热点磁贴(静态 RRO)。
APK=$MOD/files/treble-overlay-lenovo-tb321fu-systemui.apk
# 改了 src/ 之后用 REBUILD_RRO=1 重编(也可以手动跑 toolkit/lib/build-rro.sh)
[[ ${REBUILD_RRO:-0} == 1 ]] && "$TOOLKIT/lib/build-rro.sh" "$MOD/src" "$APK" 1
[[ -f $APK ]] || die "缺 $APK(先跑 toolkit/lib/build-rro.sh $MOD/src $APK)"
put "$APK" product/overlay/treble-overlay-lenovo-tb321fu-systemui.apk 0644 0:0 u:object_r:system_file:s0
