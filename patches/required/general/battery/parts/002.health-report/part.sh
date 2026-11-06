# 只读:电量、温度、两颗电芯各自的循环次数/健康度/日期/厂商,以及几个电池节点的当前值。给 herald broker 的 battery 命令加一个子命令,给 heraldctl help 加说明。
put "$MOD/files/battery-health.sh"            etc/herald_payload/plugins/battery-health.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-battery-health.sh"     etc/heraldctl.d/battery-health.sh            0644 0:0 u:object_r:system_file:s0
