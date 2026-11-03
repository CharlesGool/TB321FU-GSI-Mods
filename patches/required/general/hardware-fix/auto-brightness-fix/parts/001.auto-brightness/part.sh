# brightness/auto-brightness:静态 RRO(放进 /product/overlay 就生效),原理见本目录 README.md。
APK=$MOD/files/auto-brightness.apk
# 改了 src/ 之后用 REBUILD_RRO=1 重编(也可以手动跑 toolkit/lib/build-rro.sh)
[[ ${REBUILD_RRO:-0} == 1 ]] && "$TOOLKIT/lib/build-rro.sh" "$MOD/src" "$APK" 1
[[ -f $APK ]] || die "缺 $APK(先跑 toolkit/lib/build-rro.sh $MOD/src $APK)"
put "$APK" product/overlay/tb321fu-auto-brightness.apk 0644 0:0 u:object_r:system_file:s0
