# 游戏模式的"性能档"钩子:名单应用前台时切性能档,离开恢复。依赖 game-mode 和 perf/profiles。
require_mod required/general/herald-core
require_mod optional/game-mode
require_mod optional/perf
put "$MOD/files/perf-game.sh"         etc/herald_payload/plugins/perf-game.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-perf-game.sh"  etc/heraldctl.d/perf-game.sh            0644 0:0 u:object_r:system_file:s0
