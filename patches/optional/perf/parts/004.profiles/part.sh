# 一键切档(perf profile …):省电 / 均衡 / 性能。依赖 perf/cpu-freq;perf/gpu-freq 装了就一起调 GPU。
put "$MOD/files/perf-profiles.sh"         etc/herald_payload/plugins/perf-profiles.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf-profiles.sh"  etc/heraldctl.d/perf-profiles.sh            0644 0:0 u:object_r:system_file:s0
