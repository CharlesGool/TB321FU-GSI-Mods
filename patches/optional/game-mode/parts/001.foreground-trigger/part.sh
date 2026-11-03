# 游戏模式的核心:名单 + 前台应用监听 + 进入/离开时触发钩子(game-mode/kiosk-lock、game-mode/auto-dnd 是钩子)。
# 给 herald broker 加 game 命令,给 heraldctl 加 game 子命令。靠 herald-core 的插件机制,必须排在它后面。
put "$MOD/files/game-core.sh"      etc/herald_payload/plugins/game-core.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-game.sh"    etc/heraldctl.d/game.sh                 0644 0:0 u:object_r:system_file:s0
