# 性能调节的公共部分:给 herald broker 加 perf 命令(按子命令分发给 perf/* 各模块)和空闲时的"设置被改回去就重写",给 heraldctl 加 perf 子命令。
# 靠 herald-core 的插件机制,必须排在它后面;其他 perf/* 模块都要求它在前面。
put "$MOD/files/perf-lib.sh"      etc/herald_payload/plugins/perf-lib.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf.sh"   etc/heraldctl.d/perf.sh                0644 0:0 u:object_r:system_file:s0
