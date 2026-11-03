# 只读温度(perf temps)。依赖 perf/node-access(命令分发)。
put "$MOD/files/perf-temps.sh"         etc/herald_payload/plugins/perf-temps.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf-temps.sh"  etc/heraldctl.d/perf-temps.sh            0644 0:0 u:object_r:system_file:s0
