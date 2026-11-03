# game-mode:游戏模式:游戏名单与前台触发、锁住退出途径(导航/通知栏/快捷设置)、自动勿扰。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
