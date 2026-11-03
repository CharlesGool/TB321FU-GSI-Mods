#!/usr/bin/env bash
# 游戏模式插件(patches/optional/game-mode/*)的单元测试 + 一个后台进程冒烟测试:桩 herald_game_sysq(settings/cmd/dumpsys),
# 桩 logcat/getevent,在 dash 和 busybox sh 下各跑一遍。用法: toolkit/test-game-plugins.sh   (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
G=$REPO/patches/optional/game-mode/parts
T=$(mktemp -d "${TMPDIR:-/tmp}/gametest.XXXXXX"); trap 'pkill -f "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nochk(){ if printf '%s\n' "$2" | grep -qxF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }
eq()   { if [ "$2" = "$3" ]; then ok; else bad "$1: 期望 '$3' 实际 '$2'"; fi; }
val()  { cat "$1/$2" 2>/dev/null || echo "(无)"; }

mkenv() {   # mkenv <目录>
  rm -rf "$1"; mkdir -p "$1/bin"
  echo 0 > "$1/zen"; echo "  mCurrentFocus=Window{1 u0 com.android.launcher/.Main}" > "$1/window.txt"
  printf '#!/bin/sh\necho "I/wm_set_resumed_activity( 1): [0,com.game/.Main,test]"\nsleep 30\n' > "$1/bin/logcat"
  printf '#!/bin/sh\nsleep 1.5\nfor k in 0073 0072 0073 0072 0073 0072; do echo "/dev/input/event1: 0001 $k 00000001"; echo "/dev/input/event1: 0001 $k 00000000"; sleep 0.1; done\nsleep 30\n' > "$1/bin/getevent"
  chmod +x "$1/bin/logcat" "$1/bin/getevent"
}

run() {   # run <sh> <目录> <命令…> : 加载 game 的三个插件(字母序 core、dnd、lock),桩掉系统调用,执行
  local sh=$1 D=$2; shift 2
  cat > "$T/drv.sh" <<DRV
STATE=$D/state; W=$D/w; mkdir -p "\$STATE" "\$W"; HERALDP_IDLE=""; HERALD_GAME_BIN=$D/bin; HERALD_GAME_TPS=1; HERALD_GAME_PROC=$D/proc
blog() { echo "\$*" >> "$D/blog.txt"; }
$(sed -n '/^herald_int_in()/,/^}/p' "$REPO/patches/required/general/herald-core/files/herald-start.sh")
for f in $G/001.foreground-trigger/files/game-core.sh $G/003.auto-dnd/files/game-dnd.sh $G/002.kiosk-lock/files/game-lock.sh; do . "\$f"; done
if [ -z "\${REAL_ENSURE:-}" ]; then herald_game_ensure() { :; }; fi
FLAGS_OK="search home recents notification-peek statusbar-expansion notification-shade quick-settings back"
herald_game_sysq() {   # 桩
  case "\$2 \$3" in
    "get global") cat "$D/zen" ;;
    "put global") echo "\$5" > "$D/zen" ;;
    "notification set_dnd") [ -f "$D/dnd_broken" ] && return 0
       case "\$4" in off) echo 0 ;; priority) echo 1 ;; none) echo 2 ;; alarms) echo 3 ;; esac > "$D/zen" ;;
    "statusbar send-disable-flag") shift 3
       if [ "\$1" = none ]; then rm -f "$D/flags"; return 0; fi
       for _f in "\$@"; do case " \$FLAGS_OK " in *" \$_f "*) [ "\$_f" = "\$REJECT" ] && { echo "Unrecognized argument: \$_f"; return 1; } ;; *) echo "Unrecognized argument: \$_f"; return 1 ;; esac; done
       echo "\$*" > "$D/flags" ;;
    "window ") cat "$D/window.txt" ;;
  esac
  [ "\$2" = "\$(basename "\$2")" ] && [ "\$1" = "$D/bin/dumpsys" ] && cat "$D/window.txt"
  return 0
}
DRV
  printf '%s\n' "$@" >> "$T/drv.sh"
  $sh "$T/drv.sh" 2>&1
}
fg() { echo "$2" > "$1/w/game_fg"; }

for SH in dash "busybox sh"; do
  command -v ${SH%% *} >/dev/null || { echo "跳过 $SH(没装)"; continue; }
  echo "== $SH"
  D=$T/d; mkenv "$D"
  # --- 名单管理
  o=$(run "$SH" "$D" 'heraldp_cmd_game "status"'); chk status "$o" "enabled=on"; chk status "$o" "daemon=stopped"; chk status "$o" "hooks=dnd,lock"; chk status "$o" "apps=0"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "add com.game"; heraldp_cmd_game "add com.dnd dnd"; heraldp_cmd_game "list"')
  chk add "$o" "ok game add com.game *"; chk add "$o" "ok game add com.dnd dnd"; chk list "$o" "com.game=*"; chk list "$o" "com.dnd=dnd"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "add ../x"'); chk add-bad "$o" "err game 用法: game add <包名> [钩子名…]"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "add com.a nosuch"'); chk add-hook "$o" "err game 没有钩子 nosuch(已装:dnd lock)"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "remove com.dnd"' 'heraldp_cmd_game "remove com.dnd"'); chk remove "$o" "ok game remove com.dnd"; chk remove "$o" "err game com.dnd 不在名单里"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "bogus"'); chk unknown "$o" "err game 没有子命令 bogus(装了哪些见 heraldctl help)"
  o=$(run "$SH" "$D" 'heraldp_cmd_game ""'); chk nosub "$o" "err game 子命令只能是小写字母数字"
  o=$(run "$SH" "$D" 'heraldp_cmd_game "combo UDUD"' 'heraldp_cmd_game "combo UDX1"' 'heraldp_cmd_game "combo UD"' 'heraldp_cmd_game "flags home recents"' 'heraldp_cmd_game "flags Bad"' 'heraldp_cmd_game "dndmode none"' 'heraldp_cmd_game "dndmode foo"' 'heraldp_cmd_game "debounce 5"' 'heraldp_cmd_game "debounce x"' 'heraldp_cmd_game "status"')
  chk combo "$o" "ok game combo UDUD"; chk combo "$o" "err game 组合只能由 U(音量上)和 D(音量下)组成"; chk combo "$o" "err game 组合长度要 4~12 个"
  chk flags "$o" "ok game flags home recents"; chk flags "$o" "err game flag 只能是小写字母数字和减号: Bad"
  chk dndmode "$o" "ok game dndmode none"; chk dndmode "$o" "err game 用法: game dndmode <priority|none|alarms>"
  chk debounce "$o" "ok game debounce 5"; chk debounce "$o" "err game 用法: game debounce <0-60 秒>"
  chk status "$o" "lock_flags=home recents"; chk status "$o" "lock_combo=UDUD"; chk status "$o" "dnd_mode=none"; chk status "$o" "debounce=5"
  # --- 进入/离开(直接驱动 herald_game_tick)
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg' 'herald_game_tick' 'heraldp_cmd_game "status"')
  chk enter "$o" "active=com.game"; chk enter "$o" "active_hooks=dnd,lock"
  eq enter-zen "$(val "$D" zen)" 1
  eq enter-flags "$(val "$D" flags)" "search home recents notification-peek statusbar-expansion notification-shade quick-settings"
  chk enter "$o" "lock_applied=search home recents notification-peek statusbar-expansion notification-shade quick-settings"
  chk enter "$o" "dnd_saved=orig=0 set=1"
  # 离开:前 2 秒不动,第 3 秒才恢复
  run "$SH" "$D" 'herald_game_cset debounce 3' 'echo com.android.launcher > $W/game_fg' 'herald_game_tick' 'herald_game_tick' >/dev/null
  eq debounce-hold "$(val "$D" zen)" 1; [ -f "$D/flags" ] && ok || bad "debounce 期间不该解锁"
  # (每次 run 是新 shell,计数在 shell 里——所以同一次 run 里连着 tick)
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 3' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.android.launcher > $W/game_fg; herald_game_tick; herald_game_tick' 'echo "mid=$(cat '"$D"'/zen)"' 'herald_game_tick' 'heraldp_cmd_game "status"')
  chk leave-mid "$o" "mid=1"; chk leave "$o" "active="; eq leave-zen "$(val "$D" zen)" 0; eq leave-flags "$(val "$D" flags)" "(无)"
  [ -f "$D/state/game-dnd.state" ] && bad "dnd 状态文件应删除" || ok
  # 回到游戏时在 debounce 内:计数清零,不重复进入
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 3' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.perm > $W/game_fg; herald_game_tick; herald_game_tick' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.perm > $W/game_fg; herald_game_tick; herald_game_tick' 'heraldp_cmd_game "status"')
  chk flicker "$o" "active=com.game"
  # V84:默认(防抖 0)离开名单应用的下一个 tick 就恢复;权限弹窗/系统界面不算离开
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.android.launcher > $W/game_fg; herald_game_tick' >/dev/null
  eq leave-now "$(val "$D" zen)" 0; eq leave-now-flags "$(val "$D" flags)" "(无)"
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.google.android.permissioncontroller > $W/game_fg; herald_game_tick; herald_game_tick' 'echo com.android.systemui > $W/game_fg; herald_game_tick' >/dev/null
  eq transient-hold "$(val "$D" zen)" 1
  # 快路径:前台不变时 tick 不改任何东西;配置一变(加名单)下一个 tick 立刻进入
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'echo com.game > $W/game_fg; herald_game_tick; herald_game_tick; herald_game_cset "app.com.game" "*"; herald_game_tick' >/dev/null
  eq cfg-enter "$(val "$D" zen)" 1
  # V89:进入时记下主进程 pid;它的 oom_score_adj 一离开 0 就立刻对一次前台(不等窗口事件)
  mkenv "$D"; rm -rf "$D/state"; mkdir -p "$D/proc/4321"; echo 0 > "$D/proc/4321/oom_score_adj"
  printf '#!/bin/sh\n[ "$1" = com.game ] && echo 4321\n' > "$D/bin/pidof"; chmod +x "$D/bin/pidof"
  echo "  mCurrentFocus=Window{1 u0 com.game/.Main}" > "$D/window.txt"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'echo "pid=$GAME_PID in=$(cat '"$D"'/zen)"' 'herald_game_tick; echo "still=$(cat '"$D"'/zen)"' 'echo "  mCurrentFocus=Window{1 u0 com.android.launcher/.Main}" > '"$D"'/window.txt; echo 200 > '"$D"'/proc/4321/oom_score_adj; herald_game_tick' 'echo "out=$(cat '"$D"'/zen) fg=$(cat $W/game_fg)"')
  chk adj-pid "$o" "pid=4321 in=1"; chk adj-hold "$o" "still=1"; chk adj-exit "$o" "out=0 fg=com.android.launcher"
  # 盖在游戏上的权限框:adj 变了,对一次前台是权限控制器 → 不算离开;同一个 adj 不重复 dumpsys
  mkenv "$D"; rm -rf "$D/state"; mkdir -p "$D/proc/4321"; echo 0 > "$D/proc/4321/oom_score_adj"
  printf '#!/bin/sh\n[ "$1" = com.game ] && echo 4321\n' > "$D/bin/pidof"; chmod +x "$D/bin/pidof"
  echo "  mCurrentFocus=Window{1 u0 com.google.android.permissioncontroller/.Grant}" > "$D/window.txt"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'echo 100 > '"$D"'/proc/4321/oom_score_adj; herald_game_tick; herald_game_tick' 'echo "dlg=$(cat '"$D"'/zen)"')
  chk adj-dialog "$o" "dlg=1"
  # 进程没了:立刻离开
  mkenv "$D"; rm -rf "$D/state"; mkdir -p "$D/proc/4321"; echo 0 > "$D/proc/4321/oom_score_adj"
  printf '#!/bin/sh\n[ "$1" = com.game ] && echo 4321\n' > "$D/bin/pidof"; chmod +x "$D/bin/pidof"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'rm -rf '"$D"'/proc/4321; herald_game_tick' 'echo "dead=$(cat '"$D"'/zen)"')
  chk adj-dead "$o" "dead=0"
  # debounce 0 立刻离开
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 0' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.x > $W/game_fg; herald_game_tick' >/dev/null
  eq debounce0 "$(val "$D" zen)" 0
  # --- 本来就是勿扰:不改、不记、退出保持
  mkenv "$D"; rm -rf "$D/state"; echo 2 > "$D/zen"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 0' 'echo com.game > $W/game_fg; herald_game_tick' 'echo "in=$(cat '"$D"'/zen)"' 'echo com.x > $W/game_fg; herald_game_tick')
  chk dnd-keep "$o" "in=2"; eq dnd-keep-out "$(val "$D" zen)" 2; [ -f "$D/state/game-dnd.state" ] && bad "本来就是勿扰不该记状态" || ok
  # --- 期间被别人改过:不恢复
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 0' 'echo com.game > $W/game_fg; herald_game_tick' 'echo 3 > '"$D"'/zen' 'echo com.x > $W/game_fg; herald_game_tick' >/dev/null
  eq dnd-changed "$(val "$D" zen)" 3
  # --- cmd notification 失效时回落 settings put
  mkenv "$D"; rm -rf "$D/state"; : > "$D/dnd_broken"
  run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset debounce 0' 'echo com.game > $W/game_fg; herald_game_tick' >/dev/null
  eq dnd-fallback-in "$(val "$D" zen)" 1
  run "$SH" "$D" 'herald_game_cset debounce 0' 'echo com.x > $W/game_fg; herald_game_tick; herald_game_tick' >/dev/null
  eq dnd-fallback-out "$(val "$D" zen)" 0
  # --- flag 不被系统接受:跳过它,其余照样生效
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'REJECT=notification-shade' 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick')
  eq flag-skip "$(val "$D" flags)" "search home recents notification-peek statusbar-expansion quick-settings"
  grep -q "lock 跳过 flag notification-shade" "$D/blog.txt" && ok || bad "没记录跳过的 flag"
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset lock.flags "bogus-flag"' 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'heraldp_cmd_game "status"')
  chk flag-none "$o" "lock_applied="; chk flag-none "$o" "active_hooks=dnd"
  # --- 只用指定钩子
  mkenv "$D"; rm -rf "$D/state"
  run "$SH" "$D" 'herald_game_cset "app.com.dnd" "dnd"' 'echo com.dnd > $W/game_fg; herald_game_tick' >/dev/null
  eq only-dnd "$(val "$D" zen)" 1; eq only-dnd-flags "$(val "$D" flags)" "(无)"
  # --- 直接换另一个名单应用
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"; herald_game_cset "app.com.g2" "lock"' 'echo com.game > $W/game_fg; herald_game_tick' 'echo com.g2 > $W/game_fg; herald_game_tick' 'heraldp_cmd_game "status"')
  chk switch "$o" "active=com.g2"; chk switch "$o" "active_hooks=lock"; eq switch-zen "$(val "$D" zen)" 0
  # --- 手动解除
  mkenv "$D"; rm -rf "$D/state"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'heraldp_cmd_game "release"' 'herald_game_tick' 'herald_game_tick' 'heraldp_cmd_game "status"' 'heraldp_cmd_game "release"')
  chk release "$o" "ok game release"; chk release "$o" "active="; chk release "$o" "ok game release nothing-active"
  eq release-zen "$(val "$D" zen)" 0; eq release-flags "$(val "$D" flags)" "(无)"
  o=$(run "$SH" "$D" 'herald_game_cset "app.com.game" "*"' 'echo com.game > $W/game_fg; herald_game_tick' 'heraldp_cmd_game "release"' 'herald_game_tick' 'echo com.x > $W/game_fg; herald_game_tick; herald_game_tick; herald_game_tick' 'echo com.game > $W/game_fg; herald_game_tick' 'heraldp_cmd_game "status"')
  chk release-reenter "$o" "active=com.game"
  # --- 总开关 off 时后台进程退出
  # (见下面冒烟)
  # --- boot 恢复
  mkenv "$D"; rm -rf "$D/state"; mkdir -p "$D/state"; echo 1 > "$D/zen"; printf 'orig=0\nset=1\n' > "$D/state/game-dnd.state"; echo "home" > "$D/state/game-lock.state"; echo "home" > "$D/flags"
  run "$SH" "$D" 'heraldp_game_boot_dnd' 'heraldp_game_boot_lock' >/dev/null
  eq boot-zen "$(val "$D" zen)" 0; eq boot-flags "$(val "$D" flags)" "(无)"
  # --- 事件解析 / 组合键
  o=$(run "$SH" "$D" 'herald_game_parse_event "I/wm_set_resumed_activity( 1234): [0,com.tencent.tmgp.sgame/.SGameActivity,minimalResumeActivityLocked]"' 'herald_game_parse_event "I/wm_focused_app(  800): [0,\"com.a.b/.C\",reason]"' 'herald_game_parse_event "I/other( 1): [0,com.a/.B,x]" || echo NO' 'herald_game_parse_event "I/wm_focused_app( 1): [0,null,x]" || echo NO2')
  chk parse "$o" "com.tencent.tmgp.sgame"; chk parse "$o" "com.a.b"; chk parse "$o" "NO"; chk parse "$o" "NO2"
  o=$(run "$SH" "$D" 'for k in U D U D U D; do herald_game_combo_feed $k 100 UDUDUD 5 && echo HIT; done' 'GC_BUF=""; herald_game_combo_feed U 100 UDUD 5; herald_game_combo_feed D 101 UDUD 5; herald_game_combo_feed U 107 UDUD 5; herald_game_combo_feed D 108 UDUD 5 && echo LATE' 'GC_BUF=""; for k in D D U D U D; do herald_game_combo_feed $k 200 UDUD 5 && echo NOISE; done')
  chk combo-hit "$o" "HIT"; nochk combo-late "$o" "LATE"; chk combo-noise "$o" "NOISE"

  # --- 后台进程冒烟:拉起 -> 看到前台 -> 进入 -> 音量组合解除 -> 前台离开 -> off 收尾
  mkenv "$D"; rm -rf "$D/state"; echo "  mCurrentFocus=Window{1 u0 com.game/com.game.Main}" > "$D/window.txt"
  o=$(REAL_ENSURE=1 run "$SH" "$D" 'HERALD_GAME_TICK=0.2' 'heraldp_cmd_game "add com.game"' 'sleep 1' 'heraldp_cmd_game "status"' 'sleep 3' 'echo "after_combo=$(cat '"$D"'/zen) flags=$(cat '"$D"'/flags 2>/dev/null)"' 'heraldp_cmd_game "status"' 'heraldp_cmd_game "off"' 'sleep 1' 'heraldp_cmd_game "status"')
  chk smoke "$o" "daemon=running"; chk smoke "$o" "active=com.game"; chk smoke "$o" "foreground=com.game"
  chk smoke-combo "$o" "after_combo=0 flags="
  chk smoke-off "$o" "daemon=stopped"
  pkill -f "$D/bin/" 2>/dev/null
done
echo "通过 $pass,失败 $fail"; [ "$fail" = 0 ]
