# statusbar-netspeed:状态栏网速:framework 里加类把网速插进状态栏(不改 SystemUI 的 APK)+ heraldctl 开关和样式。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
