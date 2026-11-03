# GPU 频率上下限调节(perf gpu …)。依赖 perf/node-access。
put "$MOD/files/perf-gpu.sh"         etc/herald_payload/plugins/perf-gpu.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf-gpu.sh"  etc/heraldctl.d/perf-gpu.sh            0644 0:0 u:object_r:system_file:s0
