# ush:给 herald broker 加 ush 命令(以 root sh -c 跑整条命令,装上即用、不限时),并装无特权前端 /system/bin/ush。
# 照 debug 下别的 herald 插件(herald-readonly-shell)的做法,必须排在 herald-core 后面。
require_mod required/general/herald-core
put "$MOD/files/ush.sh" etc/herald_payload/plugins/ush.sh 0644 0:0    u:object_r:herald_exec:s0
put "$MOD/files/ush"    bin/ush                           0755 0:2000 u:object_r:system_file:s0
