#!/usr/bin/env bash
# 双击唤醒:静态 RRO 让"点按唤醒"开关可见;herald broker 插件把 Secure.double_tap_to_wake 每 5 秒同步到 /proc/gesture_control;heraldctl 加 dt2w 子命令。
# 节点标签是通用 proc,init/vendor_init 没有写权限,只能放在 herald(permissive)里做,所以必须排在 herald-core 后面。
require_mod required/general/herald-core
APK=$MOD/files/tb321fu-dt2w.apk
# 改了 src/ 之后用 REBUILD_RRO=1 重编(也可以手动跑 toolkit/lib/build-rro.sh)
[[ ${REBUILD_RRO:-0} == 1 ]] && "$TOOLKIT/lib/build-rro.sh" "$MOD/src" "$APK" 1
[[ -f $APK ]] || die "缺 $APK(先跑 toolkit/lib/build-rro.sh $MOD/src $APK)"
put "$APK"                         product/overlay/tb321fu-dt2w.apk   0644 0:0 u:object_r:system_file:s0
put "$MOD/files/dt2w.sh"           etc/herald_payload/plugins/dt2w.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-dt2w.sh" etc/heraldctl.d/dt2w.sh            0644 0:0 u:object_r:system_file:s0
