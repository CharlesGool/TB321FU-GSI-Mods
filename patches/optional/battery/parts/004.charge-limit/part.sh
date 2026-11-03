# 充电上限:到上限停充,低于 上限x回充比例 才重新充。给 herald broker 的 battery 命令加一个子命令,给 heraldctl help 加说明。
put "$MOD/files/battery-limit.sh"            etc/herald_payload/plugins/battery-limit.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-battery-limit.sh"     etc/heraldctl.d/battery-limit.sh            0644 0:0 u:object_r:system_file:s0
