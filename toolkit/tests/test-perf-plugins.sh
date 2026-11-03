#!/usr/bin/env bash
# 性能调节插件(patches/optional/perf/*)的单元测试:假的 sysfs 树(cpufreq 四个簇、kgsl devfreq、thermal_zone),
# 加上和游戏模式钩子的联动,在 dash 和 busybox sh 下各跑一遍。用法: toolkit/test-perf-plugins.sh   (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/patches/optional/perf/parts; G=$REPO/patches/optional/game-mode/parts
T=$(mktemp -d "${TMPDIR:-/tmp}/perftest.XXXXXX"); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nochk(){ if printf '%s\n' "$2" | grep -qxF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }
eq()   { if [ "$2" = "$3" ]; then ok; else bad "$1: 期望 '$3' 实际 '$2'"; fi; }
nd()   { cat "$1" 2>/dev/null || echo "(无)"; }   # 读文件

mkfake() {   # mkfake <目录>
  local S=$1; rm -rf "$S"; local C=$S/devices/system/cpu/cpufreq
  mk() { mkdir -p "$C/policy$1"; local d=$C/policy$1
    echo "$2" > $d/related_cpus; echo walt > $d/scaling_governor; echo "walt schedutil performance" > $d/scaling_available_governors; echo "$3" > $d/scaling_available_frequencies
    echo "$4" > $d/cpuinfo_min_freq; echo "$5" > $d/cpuinfo_max_freq; echo "$4" > $d/scaling_min_freq; echo "$5" > $d/scaling_max_freq; echo "$4" > $d/scaling_cur_freq; }
  mk 0 "0 1" "307200 595200 1075200 1555200 1881600 2265600" 307200 2265600
  mk 2 "2 3 4" "499200 902400 1478400 2073600 2611200 3148800" 499200 3148800
  mk 5 "5 6" "499200 902400 1478400 2073600 2611200 2956800" 499200 2956800
  mk 7 "7" "595200 1171200 1766400 2361600 2956800 3302400" 595200 3302400
  for n in 0 1 2 3 4 5 6 7; do mkdir -p $S/devices/system/cpu/cpu$n; [ $n != 0 ] && echo 1 > $S/devices/system/cpu/cpu$n/online; done
  local K=$S/class/kgsl/kgsl-3d0/devfreq; mkdir -p "$K"
  echo "231000000 349000000 500000000 650000000 800000000 1000000000" > $K/available_frequencies
  echo 231000000 > $K/min_freq; echo 1000000000 > $K/max_freq; echo 349000000 > $K/cur_freq; echo msm-adreno-tz > $K/governor
  local Z=$S/class/thermal
  tz() { mkdir -p "$Z/thermal_zone$1"; echo "$2" > "$Z/thermal_zone$1/type"; echo "$3" > "$Z/thermal_zone$1/temp"; }
  tz 0 cpu-0-0 41200; tz 1 cpu-1-1 55800; tz 2 gpuss-0 47000; tz 3 skin-msm-therm 36500; tz 4 battery 33100; tz 5 xo-therm -274000; tz 6 pa-therm 0; tz 7 quiet-therm 38800
  echo "boot-aaa" > $S/bootid
}

run() {   # run <sh> <sysroot> <状态目录> <命令…>
  local sh=$1 S=$2 ST=$3; shift 3
  cat > "$T/drv.sh" <<DRV
STATE=$ST; W=$ST/w; mkdir -p "\$STATE" "\$W"; HERALDP_IDLE=""
HERALD_PERF_SYSROOT=$S; HERALD_PERF_BOOTID=$S/bootid
blog() { echo "\$*" >> "$T/blog.txt"; }
$(sed -n '/^herald_int_in()/,/^}/p' "$REPO/patches/required/general/herald-core/files/herald-start.sh")
for f in $G/001.foreground-trigger/files/game-core.sh $P/002.cpu-freq/files/perf-cpu.sh $P/003.gpu-freq/files/perf-gpu.sh $P/001.node-access/files/perf-lib.sh $P/004.profiles/files/perf-profiles.sh $P/005.thermal-readout/files/perf-temps.sh $REPO/patches/optional/perf-game-boost/files/perf-game.sh; do . "\$f"; done
herald_game_ensure() { :; }
DRV
  printf '%s\n' "$@" >> "$T/drv.sh"
  $sh "$T/drv.sh" 2>&1
}
cpu() { nd "$1/devices/system/cpu/cpufreq/policy$2/scaling_$3_freq"; }   # cpu <sys> <簇> <min|max>
gpu() { nd "$1/class/kgsl/kgsl-3d0/devfreq/$2_freq"; }

for SH in dash "busybox sh"; do
  command -v ${SH%% *} >/dev/null || { echo "跳过 $SH(没装)"; continue; }
  echo "== $SH"
  S=$T/sys; ST=$T/state; rm -rf "$ST"; mkfake "$S"
  # --- cpu status
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu status"')
  chk cpu-status "$o" "ok perf cpu"; chk cpu-status "$o" "policies=0,2,5,7"; chk cpu-status "$o" "policy7_max=3302400"; chk cpu-status "$o" "policy0_cpus=0,1"
  chk cpu-status "$o" "policy2_governor=walt"; chk cpu-status "$o" "policy5_avail=499200,902400,1478400,2073600,2611200,2956800"; chk cpu-status "$o" "policy7_custom=:"
  # --- 百分比 / 数值 / 范围
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max 70%"')
  chk cpu-set "$o" "ok perf cpu set"; chk cpu-set "$o" "policy7 max=1766400 readback=1766400"
  eq p0-70 "$(cpu "$S" 0 max)" 1555200      # 2265600*70% = 1585920 -> 不超过的最大一档 1555200
  eq p2-70 "$(cpu "$S" 2 max)" 2073600      # 3148800*70% = 2204160 -> 2073600
  eq p5-70 "$(cpu "$S" 5 max)" 1478400      # 2956800*70% = 2069760 -> 1478400(2073600 超了)
  eq p7-70 "$(cpu "$S" 7 max)" 1766400      # 3302400*70% = 2311680 -> 1766400
  eq conf-saved "$(grep '^cpu.7.max=' "$ST/perf.conf")" "cpu.7.max=1766400"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu status"'); chk stock "$o" "policy7_stock_max=3302400"; chk custom "$o" "policy7_custom=:1766400"
  # 数值:夹在 [最低,最高] 里
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 max 99999999"'); chk clamp-hi "$o" "policy7 max=3302400 readback=3302400"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 min 1"'); chk clamp-lo "$o" "policy7 min=595200 readback=595200"
  # 最小值不能大于最大值
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 max 2000000"' 'heraldp_cmd_perf "cpu set 7 min 2500000"'); chk min-gt-max "$o" "err perf 簇 7 最小值(2500000)不能大于最大值(2000000)"
  eq min-gt-max-nowrite "$(cpu "$S" 7 min)" 595200
  # 写入顺序:先抬 min 到 2000000(max 已是 2000000),再把 max 降到 1171200 必须先降 min——这里 min 比新 max 高,应报错而不是写坏
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 min 1766400"' 'heraldp_cmd_perf "cpu set 7 max 1171200"'); chk order-err "$o" "err perf 簇 7 最小值(1766400)不能大于最大值(1171200)"
  # 升 max 同时 min 已抬高:先升 max 再写 min,不会出现 min>max
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 max stock"' 'heraldp_cmd_perf "cpu set 7 min 2956800"'); chk order-ok "$o" "policy7 min=2956800 readback=2956800"
  eq order-ok-max "$(cpu "$S" 7 max)" 3302400
  # --- stock / reset
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 min stock"' 'heraldp_cmd_perf "cpu set all max stock"')
  eq stock-min "$(cpu "$S" 7 min)" 595200; eq stock-max7 "$(cpu "$S" 7 max)" 3302400; eq stock-max0 "$(cpu "$S" 0 max)" 2265600
  grep -q '^cpu\.' "$ST/perf.conf" 2>/dev/null && bad "stock 后配置里不该留 cpu.* 键" || ok
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max 50%"' 'heraldp_cmd_perf "cpu reset"'); chk reset "$o" "ok perf cpu reset"
  eq reset-max "$(cpu "$S" 2 max)" 3148800
  # --- 参数校验
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 9 max 50%"'); chk bad-pol "$o" "err perf 没有簇 9(有:0 2 5 7)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all mid 50%"'); chk bad-kind "$o" "err perf 用法: perf cpu set <簇号|all> <min|max> <kHz|N%|stock>"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max 0%"'); chk bad-spec "$o" "err perf 值不对: 0%(写 kHz 数值、N% 或 stock)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max 150%"'); chk bad-spec2 "$o" "err perf 值不对: 150%(写 kHz 数值、N% 或 stock)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max abc"'); chk bad-spec3 "$o" "err perf 值不对: abc(写 kHz 数值、N% 或 stock)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu bogus"'); chk bad-sub "$o" "err perf 用法: perf cpu status | set <簇号|all> <min|max> <kHz|N%|stock> | governor <簇号|all> <名|stock> | online <核号|all> <on|off> | reset"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu status"'); chk gov-list "$o" "policy7_governors=walt,schedutil,performance"; chk cpu-online-st "$o" "cpu3_online=1"; chk cpu0-sw "$o" "cpu0_switchable=0"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu governor 7 performance"'); chk gov-set "$o" "policy7 governor=performance readback=performance"; eq gov-node "$(nd "$S/devices/system/cpu/cpufreq/policy7/scaling_governor")" performance
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu governor 7 bogus"'); chk gov-bad "$o" "err perf 簇 7 没有调速器 bogus(可选:walt schedutil performance)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu governor all stock"'); chk gov-stock "$o" "policy7 governor=walt readback=walt"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu online 3 off"'); chk off3 "$o" "cpu3 online=0"; eq off3-node "$(nd "$S/devices/system/cpu/cpu3/online")" 0
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu online 0 off"'); chk off0 "$o" "err perf cpu0 没有 online 节点,关不掉"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu online all off"'); chk offall "$o" "ok perf cpu online"; eq last-on "$(cat "$S"/devices/system/cpu/cpu[1-7]/online | tr -cd 1 | wc -c | tr -d " ")" 0
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu reset"'); eq reset-on "$(cat "$S"/devices/system/cpu/cpu[1-7]/online | tr -cd 1 | wc -c | tr -d " ")" 7
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "bogus"'); chk unknown "$o" "err perf 没有子命令 bogus(装了哪些性能模块看 heraldctl help)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf ""'); chk nosub "$o" "err perf 子命令只能是小写字母数字"
  # 写不进去(节点只读)
  if [ "$(id -u)" != 0 ]; then
    chmod a-w "$S/devices/system/cpu/cpufreq/policy5/scaling_max_freq"
    o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 5 max 50%"'); chk ro "$o" "err perf 簇 5 写不进 scaling_max_freq"
    chmod u+w "$S/devices/system/cpu/cpufreq/policy5/scaling_max_freq"
  fi
  # --- 重新套用:被别人改回去
  mkfake "$S"; rm -rf "$ST"
  run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 max 50%"' >/dev/null
  echo 3302400 > "$S/devices/system/cpu/cpufreq/policy7/scaling_max_freq"
  run "$SH" "$S" "$ST" 'heraldp_perf_reapply_cpu' >/dev/null
  eq reapply "$(cpu "$S" 7 max)" 1171200     # 3302400*50% = 1651200 -> 1171200
  # 开机后(新的 boot_id)第一次:先记出厂值再写——模拟内核出厂值已变
  echo "boot-bbb" > "$S/bootid"; echo 3302400 > "$S/devices/system/cpu/cpufreq/policy7/scaling_max_freq"; echo 1171200 > "$S/devices/system/cpu/cpufreq/policy7/scaling_min_freq"
  run "$SH" "$S" "$ST" 'heraldp_perf_reapply_cpu' >/dev/null
  eq reboot-reapply "$(cpu "$S" 7 max)" 1171200
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 7 min stock"'); eq reboot-stock-min "$(cpu "$S" 7 min)" 1171200
  grep -q '^boot=boot-bbb' "$ST/perf.stock" && ok || bad "出厂值文件应换成新的 boot_id"
  # --- idle 调度:第一次空闲就核对
  mkfake "$S"; rm -rf "$ST"
  run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set 2 max 50%"' >/dev/null
  echo 3148800 > "$S/devices/system/cpu/cpufreq/policy2/scaling_max_freq"
  run "$SH" "$S" "$ST" 'heraldp_perf_idle' >/dev/null; eq idle "$(cpu "$S" 2 max)" 1478400
  o=$(run "$SH" "$S" "$ST" 'echo "IDLE=$HERALDP_IDLE"'); chk idle-reg "$o" "IDLE= heraldp_game_idle heraldp_perf_idle"
  # --- gpu
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu status"'); chk gpu-status "$o" "ok perf gpu"; chk gpu-status "$o" "max=1000000000"; chk gpu-status "$o" "avail=231000000,349000000,500000000,650000000,800000000,1000000000"; chk gpu-status "$o" "governor=msm-adreno-tz"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set max 60%"'); chk gpu-set "$o" "max=500000000 readback=500000000"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set min 349MHz"'); chk gpu-mhz "$o" "min=349000000 readback=349000000"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set min 650MHz"'); chk gpu-order "$o" "err perf GPU 最小值(650000000)不能大于最大值(500000000)"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set max 800000000"'); eq gpu-hz "$(gpu "$S" max)" 800000000
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu reset"'); chk gpu-reset "$o" "ok perf gpu reset"; eq gpu-reset-max "$(gpu "$S" max)" 1000000000; eq gpu-reset-min "$(gpu "$S" min)" 231000000
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set max bogus"'); chk gpu-bad "$o" "err perf 值不对: bogus(写 Hz、NMHz、N% 或 stock)"
  run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu set max 60%"' >/dev/null; echo 1000000000 > "$S/class/kgsl/kgsl-3d0/devfreq/max_freq"
  run "$SH" "$S" "$ST" 'heraldp_perf_reapply_gpu' >/dev/null; eq gpu-reapply "$(gpu "$S" max)" 500000000
  rm -rf "$S/class/kgsl"; o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "gpu status"'); chk gpu-none "$o" "err perf 这台机器没有 GPU 频率节点($S/class/kgsl/kgsl-3d0/devfreq)"
  # --- 档位
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile"'); chk prof-default "$o" "profile=balanced"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile powersave"' 'heraldp_cmd_perf "profile"'); chk prof-ps "$o" "ok perf profile powersave"; chk prof-ps "$o" "profile=powersave"
  eq ps-p7 "$(cpu "$S" 7 max)" 1766400; eq ps-p0 "$(cpu "$S" 0 max)" 1075200   # 2265600*60% = 1359360 -> 1075200
  eq ps-gpu "$(gpu "$S" max)" 500000000; eq ps-min "$(cpu "$S" 7 min)" 595200
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile performance"' 'heraldp_cmd_perf "profile"'); chk prof-pf "$o" "profile=performance"
  eq pf-max "$(cpu "$S" 7 max)" 3302400; eq pf-min7 "$(cpu "$S" 7 min)" 1171200; eq pf-min0 "$(cpu "$S" 0 min)" 595200; eq pf-gpu "$(gpu "$S" max)" 1000000000   # 3302400*40% = 1320960 -> 1171200;2265600*40% = 906240 -> 595200
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile balanced"' 'heraldp_cmd_perf "profile"'); chk prof-bal "$o" "profile=balanced"
  eq bal-min "$(cpu "$S" 7 min)" 595200; eq bal-max "$(cpu "$S" 0 max)" 2265600
  grep -qE '^(cpu|gpu)\.' "$ST/perf.conf" 2>/dev/null && bad "balanced 后不该留 cpu/gpu 键" || ok
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile powersave"' 'heraldp_cmd_perf "cpu set 7 max 90%"' 'heraldp_cmd_perf "profile"'); chk prof-custom "$o" "profile=custom"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile turbo"'); chk prof-bad "$o" "err perf 用法: perf profile [status] | powersave | balanced | performance"
  # 没有 GPU 节点时档位只调 CPU
  rm -rf "$S/class/kgsl"; o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "profile performance"'); chk prof-nogpu "$o" "ok perf profile performance"
  # --- 温度
  mkfake "$S"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "temps"'); chk temps "$o" "ok perf temps"; chk temps "$o" "cpu_max_c=55.8"; chk temps "$o" "gpu_max_c=47.0"; chk temps "$o" "skin_c=36.5"; chk temps "$o" "battery_c=33.1"
  chk temps "$o" "hottest_c=55.8"; chk temps "$o" "hottest_zone=cpu-1-1"; chk temps "$o" "zones=6"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "temps all"'); chk temps-all "$o" "zone.quiet-therm=38.8"; nochk temps-all "$o" "zone.xo-therm=-27.4"
  rm -rf "$S/class/thermal"; o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "temps"'); chk temps-none "$o" "err perf 读不到 thermal_zone($S/class/thermal)"
  # --- 游戏联动:进入切性能档,离开原样恢复(包括手动调的 custom)
  mkfake "$S"; rm -rf "$ST"
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_perf "cpu set all max 70%"' 'herald_game_cset "app.com.game" "*"' 'herald_game_enter com.game "*"' 'heraldp_cmd_perf "profile"' 'heraldp_game_status_perf' 'herald_game_exit' 'heraldp_cmd_perf "profile"')
  chk game "$o" "profile=performance"; chk game "$o" "perf_game_profile=performance"; chk game "$o" "profile=custom"
  eq game-restore-max "$(cpu "$S" 7 max)" 1766400; eq game-restore-min "$(cpu "$S" 7 min)" 595200
  [ -f "$ST/perf-game.state" ] && bad "离开后快照文件应删除" || ok
  # 进入后 performance 抬了 min
  run "$SH" "$S" "$ST" 'herald_game_enter com.game "*"' >/dev/null; eq game-in-min "$(cpu "$S" 7 min)" 1171200
  # 异常中断后 boot 恢复
  run "$SH" "$S" "$ST" 'heraldp_game_boot_perf' >/dev/null; eq game-boot "$(cpu "$S" 7 min)" 595200
  # 改档位
  o=$(run "$SH" "$S" "$ST" 'heraldp_cmd_game "perfprofile powersave"' 'heraldp_cmd_game "perfprofile x"'); chk game-pp "$o" "ok game perfprofile powersave"; chk game-pp "$o" "err game 用法: game perfprofile <performance|powersave|balanced>"
  run "$SH" "$S" "$ST" 'herald_game_enter com.game "*"' >/dev/null; eq game-ps "$(cpu "$S" 7 max)" 1766400
  run "$SH" "$S" "$ST" 'herald_game_exit' >/dev/null
  # 只用别的钩子时不动性能
  mkfake "$S"; rm -rf "$ST"
  run "$SH" "$S" "$ST" 'herald_game_enter com.game "lock"' >/dev/null; eq game-no-perf "$(cpu "$S" 7 min)" 595200
  # 钩子已注册
  o=$(run "$SH" "$S" "$ST" 'echo "H=$GAME_HOOKS"'); chk hook-reg "$o" "H= perf"
done
echo "通过 $pass,失败 $fail"; [ "$fail" = 0 ]
