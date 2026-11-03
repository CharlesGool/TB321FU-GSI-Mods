# game-mode/auto-dnd 的 broker 插件(装在 /system/etc/herald_payload/plugins/game-dnd.sh)。game-mode/foreground-trigger 的钩子 "dnd"。
# 进入名单应用时开勿扰,离开时恢复原值:
#   - 进入时本来就是勿扰(zen_mode != 0):什么都不改,也不记任何东西——离开时自然保持勿扰;
#   - 进入时是关着的(zen_mode = 0):按 dnd.mode 开勿扰,并记下"原值=0、我设的值=N";离开时如果当前值还是我设的,
#     就恢复成 0;如果期间被别人改过(当前值 != 我设的),不动。
#   - 记在 $STATE/game-dnd.state,后台进程重启/整机重启后靠它补上"离开"的恢复,不会把勿扰留在开着的状态。
# 做法:先 `cmd notification set_dnd <priority|none|alarms|off>`,再读 settings global zen_mode 核对;不对就直接 `settings put global zen_mode`。
# 命令: game dndmode <priority|none|alarms>  开哪种勿扰(默认 priority = 仅允许优先打扰,闹钟照响)
GAME_DND_STATE=$STATE/game-dnd.state
GAME_HOOKS="${GAME_HOOKS:-} dnd"
herald_game_zen_get() { herald_game_sysq "$GAME_BIN/settings" get global zen_mode | tr -d '\r\n'; }
herald_game_zen_name() { case "$1" in 0) echo off ;; 1) echo priority ;; 2) echo none ;; 3) echo alarms ;; esac; }
herald_game_zen_set() {             # $1 目标值 0-3;设成并读回确认才返回 0
  _gzn=$(herald_game_zen_name "$1"); [ -n "$_gzn" ] || return 1
  herald_game_sysq "$GAME_BIN/cmd" notification set_dnd "$_gzn" >/dev/null
  [ "$(herald_game_zen_get)" = "$1" ] && return 0
  herald_game_sysq "$GAME_BIN/settings" put global zen_mode "$1" >/dev/null
  [ "$(herald_game_zen_get)" = "$1" ]
}
herald_game_dnd_val() { case "$(herald_game_cget dnd.mode)" in none) echo 2 ;; alarms) echo 3 ;; *) echo 1 ;; esac; }
heraldp_game_enter_dnd() {
  _gz=$(herald_game_zen_get)
  case "$_gz" in 0) ;; 1|2|3) blog "game: dnd 进入时已是勿扰($_gz),不改"; return 0 ;; *) blog "game: dnd 读不到 zen_mode($_gz),不改"; return 1 ;; esac
  _gzv=$(herald_game_dnd_val)
  if herald_game_zen_set "$_gzv"; then printf 'orig=0\nset=%s\n' "$_gzv" > "$GAME_DND_STATE"; blog "game: dnd 已开($(herald_game_zen_name "$_gzv"))"; return 0; fi
  blog "game: dnd 没设成功"; return 1
}
heraldp_game_exit_dnd() {
  [ -f "$GAME_DND_STATE" ] || return 0                 # 进入时就是勿扰(或没做成)——保持原样
  _gzo=0; _gzs=""
  while IFS= read -r _gl; do case "$_gl" in orig=*) _gzo=${_gl#orig=} ;; set=*) _gzs=${_gl#set=} ;; esac; done < "$GAME_DND_STATE"
  _gzc=$(herald_game_zen_get)
  if [ "$_gzc" = "$_gzs" ]; then
    herald_game_zen_set "$_gzo" && blog "game: dnd 恢复为 $_gzo" || blog "game: dnd 恢复 $_gzo 失败"
  else blog "game: dnd 期间被改成 $_gzc(我设的是 $_gzs),不恢复"; fi
  rm -f "$GAME_DND_STATE"; return 0
}
heraldp_game_boot_dnd() { [ -f "$GAME_DND_STATE" ] && { blog "game: dnd 上次没收拾干净,现在恢复"; heraldp_game_exit_dnd; }; return 0; }
heraldp_game_status_dnd() {
  echo "dnd_mode=$(herald_game_zen_name "$(herald_game_dnd_val)")"
  [ -f "$GAME_DND_STATE" ] && echo "dnd_saved=$(tr '\n' ' ' < "$GAME_DND_STATE" | sed 's/ $//')" || echo "dnd_saved="
}
heraldp_game_sub_dndmode() {
  case "$1" in priority|none|alarms) herald_game_cset dnd.mode "$1"; echo "ok game dndmode $1" ;; *) echo "err game 用法: game dndmode <priority|none|alarms>" ;; esac
}
