# power-profile:静态 RRO,把 framework-res 的 power_profile 换成 vendor 版 + audio/video 新键名。
APK=$MOD/files/tb321fu-power-profile.apk
[[ ${REBUILD_RRO:-0} == 1 ]] && "$TOOLKIT/lib/build-rro.sh" "$MOD/src" "$APK" 1
[[ -f $APK ]] || die "缺 $APK(先跑 toolkit/lib/build-rro.sh $MOD/src $APK)"
put "$APK" product/overlay/tb321fu-power-profile.apk 0644 0:0 u:object_r:system_file:s0
