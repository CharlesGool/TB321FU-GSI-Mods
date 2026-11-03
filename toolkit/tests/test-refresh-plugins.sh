#!/usr/bin/env bash
# 刷新率插件(patches/optional/refresh-control 的 control 部分和 patches/optional/refresh-auto-switch)的单元测试:桩 herald_sys(settings/dumpsys),在 dash 和 busybox sh 下各跑一遍。
# dumpsys display / window 的样本取自真机(TB321FU)的真实格式。用法: toolkit/test-refresh-plugins.sh   (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/patches/optional/refresh-control; A=$REPO/patches/optional/refresh-auto-switch
T=$(mktemp -d "${TMPDIR:-/tmp}/reftest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nochk(){ if printf '%s\n' "$2" | grep -qxF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }

mkdumps() {   # mkdumps <目录> : 假的 dumpsys 输出
  mkdir -p "$1/set"
  cat > "$1/display.txt" <<'D'
  mBaseDisplayInfo=DisplayInfo{"内置屏幕", displayId 0, supportedModes [{id=1, width=1600, height=2560, fps=120.00001, vsync=120.00001, synthetic=false, alternativeRefreshRates=[30.000002, 60.000004, 90.0, 144.00002, 165.0], supportedHdrTypes=[2, 3]}, {id=2, width=1600, height=2560, fps=165.0, vsync=165.0, synthetic=false, alternativeRefreshRates=[30.000002], supportedHdrTypes=[2, 3]}, {id=3, width=1600, height=2560, fps=144.00002, vsync=144.00002, synthetic=false, alternativeRefreshRates=[], supportedHdrTypes=[2, 3]}, {id=4, width=1600, height=2560, fps=90.0, vsync=90.0, synthetic=false, alternativeRefreshRates=[], supportedHdrTypes=[]}, {id=5, width=1600, height=2560, fps=60.000004, vsync=60.000004, synthetic=false, alternativeRefreshRates=[], supportedHdrTypes=[]}, {id=6, width=1600, height=2560, fps=30.000002, vsync=30.000002, synthetic=false, alternativeRefreshRates=[], supportedHdrTypes=[]}]
    mActiveSfDisplayMode=DisplayMode{id=1, width=1600, height=2560, xDpi=344.406, yDpi=342.231, peakRefreshRate=120.00001, vsyncRate=120.00001, appVsyncOffsetNanos=75758, group=0}
D
  echo "  mCurrentFocus=Window{4f2a1c u0 com.android.chrome/org.chromium.chrome.browser.ChromeTabbedActivity}" > "$1/window.txt"
}

run() {   # run <sh> <目录> <命令…> : 加载两个插件(adaptive 在前,模拟字母序),执行
  local sh=$1 D=$2; shift 2
  cat > "$T/drv.sh" <<DRV
STATE=$D/state; W=$D/w; mkdir -p "\$STATE" "\$W"; HERALDP_IDLE=""
HERALD_REF_SYSROOT=$D/sys
blog() { echo "\$*" >> "$D/blog.txt"; }
$(sed -n '/^herald_int_in()/,/^}/p' "$REPO/patches/required/general/herald-core/files/herald-start.sh")
herald_sys() {   # 桩:settings get/put/delete system 键值落在 $D/set;dumpsys 吐样本
  case "\$1 \$2" in
    "/system/bin/settings get") [ -f "$D/set/\$4" ] && cat "$D/set/\$4" || echo null ;;
    "/system/bin/settings put") echo "\$5" > "$D/set/\$4" ;;
    "/system/bin/settings delete") rm -f "$D/set/\$4" ;;
    "/system/bin/dumpsys display") cat "$D/display.txt" ;;
    "/system/bin/dumpsys window") cat "$D/window.txt" ;;
  esac
}
. $A/files/adaptive-refresh.sh
. $M/files/refresh-rate.sh
DRV
  printf '%s\n' "$@" >> "$T/drv.sh"
  $sh "$T/drv.sh" 2>&1
}
setting() { cat "$1/set/$2" 2>/dev/null || echo "(无)"; }

for SH in dash "busybox sh"; do
  command -v ${SH%% *} >/dev/null || { echo "跳过 $SH(没装)"; continue; }
  echo "== $SH"
  D=$T/d; rm -rf "$D"; mkdumps "$D"; mkdir -p "$D/sys/class/power_supply/battery"
  echo 80 > "$D/sys/class/power_supply/battery/capacity"; echo Discharging > "$D/sys/class/power_supply/battery/status"
  # --- modes / status
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "modes"'); chk modes "$o" "modes=30,60,90,120,144,165"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "status"'); chk status "$o" "active=120"; chk status "$o" "modes=30,60,90,120,144,165"; chk status "$o" "mode=manual"
  # --- set / range / auto
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "set 60"'); chk set "$o" "ok refresh set 60"
  [ "$(setting "$D" min_refresh_rate)" = 60 ] && [ "$(setting "$D" peak_refresh_rate)" = 60 ] && ok || bad "set 60 没写 min/peak"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "set 75"'); chk set-bad "$o" "err refresh 75 不是面板支持的档位(30,60,90,120,144,165)"
  [ "$(setting "$D" peak_refresh_rate)" = 60 ] && ok || bad "非法档位不该改设置"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "set abc"'); chk set-nan "$o" "err refresh 用法: refresh set <Hz>"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "range 60 120"'); chk range "$o" "ok refresh range 60-120"
  [ "$(setting "$D" min_refresh_rate)" = 60 ] && [ "$(setting "$D" peak_refresh_rate)" = 120 ] && ok || bad "range 60 120"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "range 0 90"'); chk range0 "$o" "ok refresh range 0-90"
  [ "$(setting "$D" min_refresh_rate)" = "(无)" ] && [ "$(setting "$D" peak_refresh_rate)" = 90 ] && ok || bad "range 0 90 应删 min、peak=90"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "range 60 0"'); chk range-nomax "$o" "ok refresh range 60-0"
  [ "$(setting "$D" peak_refresh_rate)" = Infinity ] && ok || bad "range 60 0 peak 应为 Infinity"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "range 120 60"'); chk range-rev "$o" "err refresh 最小值不能大于最大值"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "auto"'); chk auto "$o" "ok refresh auto"
  [ "$(setting "$D" min_refresh_rate)" = "(无)" ] && [ "$(setting "$D" peak_refresh_rate)" = "(无)" ] && ok || bad "auto 应删两个键"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh ""'); chk nosub "$o" "err refresh 子命令只能是小写字母数字"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "bogus"'); chk unknown "$o" "err refresh 没有子命令 bogus(装了哪些见 heraldctl help)"
  # --- adaptive:规则校验
  rm -rf "$D/state"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "app com.android.chrome 60"'); chk app "$o" "ok refresh app com.android.chrome 60"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "app com.game 75"'); chk app-bad "$o" "err refresh 规格不对: 75(auto|Hz|最小-最大|off,档位见 refresh modes)"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "app ../etc 60"'); chk app-pkg "$o" "err refresh 用法: refresh app <包名> <auto|Hz|最小-最大|off>"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "app com.game 90-165"' 'heraldp_cmd_refresh "apps"'); chk apps "$o" "com.android.chrome=60"; chk apps "$o" "com.game=90-165"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "app com.game off"' 'heraldp_cmd_refresh "apps"'); nochk app-off "$o" "com.game=90-165"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "default 120"'); chk default "$o" "ok refresh default 120"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "default 77"'); chk default-bad "$o" "err refresh 用法: refresh default <auto|Hz|最小-最大>(档位见 refresh modes)"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "battery 20 60"'); chk battery "$o" "ok refresh battery 20 60"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "battery 20 auto"'); chk battery-auto "$o" "err refresh 封顶规格要写具体数值"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "battery 0 60"'); chk battery-0 "$o" "err refresh 用法: refresh battery <1-99> <Hz|最小-最大> 或 refresh battery off"
  # --- adaptive:自动切换
  rm -rf "$D/set" "$D/blog.txt"; mkdir -p "$D/set"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"' 'heraldp_cmd_refresh "adaptive status"')
  chk adp-on "$o" "ok refresh adaptive on"; chk adp-st "$o" "adaptive=on"; chk adp-st "$o" "foreground=com.android.chrome"; chk adp-st "$o" "applied=60"
  [ "$(setting "$D" peak_refresh_rate)" = 60 ] && ok || bad "chrome 规则 60 没套上"
  # 前台换成没规则的应用 -> 默认 120
  echo "  mCurrentFocus=Window{1 u0 com.other/com.other.Main}" > "$D/window.txt"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"' 'heraldp_ref_idle' 'heraldp_ref_idle'); [ "$(setting "$D" peak_refresh_rate)" = 120 ] && ok || bad "默认 120 没套上"
  # 前台 mCurrentFocus=null -> 看 mFocusedApp
  printf '  mCurrentFocus=null\n  mFocusedApp=ActivityRecord{ab u0 com.android.chrome/.Main t12}\n' > "$D/window.txt"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"'); [ "$(setting "$D" peak_refresh_rate)" = 60 ] && ok || bad "mFocusedApp 兜底失败"
  # 低电量封顶:电量 15<20、放电,默认 120 -> 封到 60
  echo "  mCurrentFocus=Window{1 u0 com.other/com.other.Main}" > "$D/window.txt"; echo 15 > "$D/sys/class/power_supply/battery/capacity"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"'); [ "$(setting "$D" peak_refresh_rate)" = 60 ] && ok || bad "低电量封顶 60 没生效($(setting "$D" peak_refresh_rate))"
  # 充电时不封顶
  echo Charging > "$D/sys/class/power_supply/battery/status"
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"'); [ "$(setting "$D" peak_refresh_rate)" = 120 ] && ok || bad "充电时不该封顶"
  # 范围封顶 + auto 封顶
  echo Discharging > "$D/sys/class/power_supply/battery/status"
  o=$(run "$SH" "$D" 'herald_ref_cap_apply 90-165 60' 'herald_ref_cap_apply 120-0 60' 'herald_ref_cap_apply auto 60' 'herald_ref_cap_apply 30 60' 'herald_ref_cap_apply 144 60' 'herald_ref_cap_apply 90 auto')
  chk cap "$o" "60-60"; chk cap "$o" "0-60"; chk cap "$o" "30"; chk cap "$o" "60"; chk cap "$o" "90"
  # adaptive off:恢复默认并清掉模式
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive off"' 'heraldp_cmd_refresh "adaptive status"'); chk adp-off "$o" "ok refresh adaptive off"; chk adp-off "$o" "adaptive=off"
  [ "$(setting "$D" peak_refresh_rate)" = "(无)" ] && ok || bad "adaptive off 应恢复系统默认"
  # 手动 set 会退出自动模式
  o=$(run "$SH" "$D" 'heraldp_cmd_refresh "adaptive on"' 'heraldp_cmd_refresh "set 90"' 'heraldp_cmd_refresh "adaptive status"'); chk manual-exits "$o" "adaptive=off"
  # 空闲函数:非自动模式不动设置
  rm -rf "$D/set"; mkdir -p "$D/set"
  o=$(run "$SH" "$D" 'heraldp_ref_idle'); [ "$(setting "$D" peak_refresh_rate)" = "(无)" ] && ok || bad "非自动模式 idle 不该写设置"
  # 注册到 HERALDP_IDLE
  o=$(run "$SH" "$D" 'echo "IDLE=$HERALDP_IDLE"'); chk idle-reg "$o" "IDLE= heraldp_ref_idle"
done
echo "通过 $pass,失败 $fail"; [ "$fail" = 0 ]
