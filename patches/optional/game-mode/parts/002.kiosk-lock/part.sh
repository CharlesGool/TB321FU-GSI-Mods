# 游戏模式的"锁住退出途径":名单应用在前台时,禁掉导航/最近任务/下拉通知栏/快捷设置,只能靠音量键组合或 heraldctl game release 退出。
# 是 game-mode/foreground-trigger 的钩子,所以要排在它后面。
put "$MOD/files/game-lock.sh"           etc/herald_payload/plugins/game-lock.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-game-lock.sh"    etc/heraldctl.d/game-lock.sh            0644 0:0 u:object_r:system_file:s0
