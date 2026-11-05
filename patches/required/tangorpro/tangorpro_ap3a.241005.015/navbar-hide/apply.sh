# navbar-hide:隐藏导航栏:三个非静态 overlay(手机模式导航栏、手势提示线、平板任务栏)+ heraldctl 开关和导航模式守护。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
