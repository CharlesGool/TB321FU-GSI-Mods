# 游戏模式的"自动勿扰":名单应用在前台时开勿扰,离开恢复原值(本来就是勿扰就不动)。是 game-mode/foreground-trigger 的钩子。
put "$MOD/files/game-dnd.sh"           etc/herald_payload/plugins/game-dnd.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-game-dnd.sh"    etc/heraldctl.d/game-dnd.sh            0644 0:0 u:object_r:system_file:s0
