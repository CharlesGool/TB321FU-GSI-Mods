# gsi-hide:去掉 GSI / 虚拟机痕迹:partition.*.verified 改 1、去掉虚拟机属性标签。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
