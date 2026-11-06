# 电池相关命令的公共部分:给 herald broker 加 battery 命令(按子命令分发给 battery/* 各模块)和空闲时的"设置被改回去就重写"调度,
# 给 heraldctl 加 battery 子命令。靠 herald-core 的插件机制,所以必须排在 herald-core 后面;其他 battery/* 模块都要求它在前面。
put "$MOD/files/battery-lib.sh"      etc/herald_payload/plugins/battery-lib.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-battery.sh"   etc/heraldctl.d/battery.sh                0644 0:0 u:object_r:system_file:s0
