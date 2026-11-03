# perf/game-boost 的 broker 插件(装在 /system/etc/herald_payload/plugins/perf-game.sh)。game-mode/foreground-trigger 的钩子 "perf"。
# 名单里的应用进前台时切到性能档(默认 performance,可改),离开后把进入前的设置原样恢复(包括手动调过的 custom)。
#   game perfprofile <performance|powersave|balanced>   进入游戏时用哪个档位
# 注意:`game add <包名>` 不写钩子名 = 所有已装钩子,装了本模块后默认也会切性能档;只想锁定/勿扰就 `game add <包名> lock dnd`。
PERF_GAME_STATE=$STATE/perf-game.state                 # 进入前的快照(有这个文件 = 现在处在游戏里)
GAME_HOOKS="${GAME_HOOKS:-} perf"
heraldp_game_enter_perf() {
  [ -f "$PERF_GAME_STATE" ] || herald_perf_snapshot > "$PERF_GAME_STATE"
  _pg=$(herald_perf_cget game_profile); herald_perf_profile_apply "${_pg:-performance}"
}
heraldp_game_exit_perf() {
  [ -f "$PERF_GAME_STATE" ] || return 0
  herald_perf_restore_snapshot "$PERF_GAME_STATE"; rm -f "$PERF_GAME_STATE"; return 0
}
heraldp_game_boot_perf() { [ -f "$PERF_GAME_STATE" ] && { blog "perf: 上次游戏中途退出,恢复进入前的设置"; heraldp_game_exit_perf; }; return 0; }
heraldp_game_status_perf() { _pg=$(herald_perf_cget game_profile); echo "perf_game_profile=${_pg:-performance}"; echo "perf_profile=$(herald_perf_profile_name)"; }
heraldp_game_sub_perfprofile() {
  case "$1" in performance|powersave|balanced) herald_perf_cset game_profile "$1"; echo "ok game perfprofile $1" ;; *) echo "err game 用法: game perfprofile <performance|powersave|balanced>" ;; esac
}
