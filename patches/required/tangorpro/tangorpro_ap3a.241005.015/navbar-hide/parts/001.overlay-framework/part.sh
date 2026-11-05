# 导航栏隐藏的一个 RRO(非静态,默认关;由 navbar-hide/control 用 cmd overlay 开关)。
# 每个 APK 必须单独一个目录:同一目录放多个包名不同的 APK 会被当成一个包的拆分包,整目录作废(V65 真机)。
[[ ${REBUILD_RRO:-0} == 1 ]] && "$MOD/build.sh"
[[ -f $MOD/files/OmkNavHideFw.apk ]] || die "缺 $MOD/files/OmkNavHideFw.apk(先跑 $MOD/build.sh)"
put_dir product/overlay/OmkNavHideFw 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/OmkNavHideFw.apk" product/overlay/OmkNavHideFw/OmkNavHideFw.apk 0644 0:0 u:object_r:system_file:s0
