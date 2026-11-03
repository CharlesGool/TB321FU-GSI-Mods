# CPU 每个簇的频率上下限调节(perf cpu …)。依赖 perf/node-access。
put "$MOD/files/perf-cpu.sh"         etc/herald_payload/plugins/perf-cpu.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf-cpu.sh"  etc/heraldctl.d/perf-cpu.sh            0644 0:0 u:object_r:system_file:s0
