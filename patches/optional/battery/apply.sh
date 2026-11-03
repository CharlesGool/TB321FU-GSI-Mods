# battery:电池:寿命查看、长期插电保护、充电上限、旁路充电(heraldctl battery …)。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
