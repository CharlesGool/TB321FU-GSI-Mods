# 旁路充电:接着充电器时电池不再充电,整机用充电器供电。给 herald broker 的 battery 命令加一个子命令,给 heraldctl help 加说明。
put "$MOD/files/battery-bypass.sh"            etc/herald_payload/plugins/battery-bypass.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-battery-bypass.sh"     etc/heraldctl.d/battery-bypass.sh            0644 0:0 u:object_r:system_file:s0
