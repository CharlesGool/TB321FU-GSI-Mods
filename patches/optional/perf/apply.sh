# perf:性能调节:CPU 各簇频率上下限、GPU 频率上下限、省电/均衡/性能一键切档、CPU/GPU/外壳/电池温度读数(heraldctl perf …)。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
