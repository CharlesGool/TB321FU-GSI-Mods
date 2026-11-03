# devopts-hide:按 App 隐藏开发者选项 / ADB 状态:framework.jar 里加类 + 四处钩子,名单里的 App 读这几项设置得到 0;heraldctl hide devopts 管开关、模式和名单,改完重启生效。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
