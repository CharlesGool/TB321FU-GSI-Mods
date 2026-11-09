#!/usr/bin/env bash
# 双击唤醒:给 herald broker 加 dt2w 插件(开机 fabricated overlay + 每 5 秒按设置同步 /proc/gesture_control),给 heraldctl 加 dt2w 子命令。
# 节点标签是通用 proc,init/vendor_init 没有写权限,只能放在 herald(permissive)里做,所以必须排在 herald-core 后面。
require_mod required/general/herald-core
put "$MOD/files/dt2w.sh"           etc/herald_payload/plugins/dt2w.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-dt2w.sh" etc/heraldctl.d/dt2w.sh            0644 0:0 u:object_r:system_file:s0
