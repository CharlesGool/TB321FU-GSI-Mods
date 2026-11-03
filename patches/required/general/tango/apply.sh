# tango:32 位 APK 支持(Tango 二进制翻译):翻译器 + sepolicy + 内核模块 + 32 位 vendor 库 + 32 位 zygote 和开机保险(授权文件不进仓库)。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
