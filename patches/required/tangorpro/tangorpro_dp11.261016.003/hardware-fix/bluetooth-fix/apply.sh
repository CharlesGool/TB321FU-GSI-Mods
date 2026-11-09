# bluetooth-fix:蓝牙音频修复:关 A2DP 硬件 offload 和 LE Audio,改走 vendor 软件编码;音频策略和 audio.primary 去掉对应检查(开机 bind 到 vendor),修耳机没声音和通话听不到。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
