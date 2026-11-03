# rotation-fix:屏幕方向修复:只能横屏的应用画面不再倒过来;去掉 Pixel Tablet 底座的方向设置(两个静态 RRO)。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
