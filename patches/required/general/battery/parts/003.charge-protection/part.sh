# 长期插电保护:电量保持在 [min,max] 区间。给 herald broker 的 battery 命令加一个子命令,给 heraldctl help 加说明。
put "$MOD/files/battery-protect.sh"            etc/herald_payload/plugins/battery-protect.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-battery-protect.sh"     etc/heraldctl.d/battery-protect.sh            0644 0:0 u:object_r:system_file:s0
