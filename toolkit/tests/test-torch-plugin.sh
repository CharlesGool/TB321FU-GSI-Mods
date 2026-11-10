#!/usr/bin/env bash
# torch-levels 插件的单元测试:假的 /sys/class/leds(记录每次写入的顺序)+ 桩 getprop,在 mksh / dash / busybox sh 下跑。
# 用法: toolkit/tests/test-torch-plugin.sh      (不碰真机,不需要 root)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/patches/required/general/hardware-fix/torch-levels/files/torch.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/torchtest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; echo "      得到: $2"; echo "      应为: $3"; fi; }
for SH in mksh dash "busybox sh"; do
  command -v ${SH%% *} >/dev/null || { echo "跳过 $SH(没装)"; continue; }
  echo "== $SH"
  run() {   # run <switch_2 初值> <属性名> <属性值> <命令> [被摘掉 trigger 的 LED…]:输出回包 + 写入日志 + 最后的 trigger
    rm -rf "$T/sys" "$T/st"; mkdir -p "$T/st"; for n in switch_2 torch_0 torch_3 flash_0 flash_3; do mkdir -p "$T/sys/class/leds/led:$n"; done
    for n in torch_0 torch_3 switch_2; do   # 假 trigger 文件:当前项带 [],写 0 时(模拟内核)换成 [none]
      echo "none [$(echo "$n" | tr -d _)_trigger] flash0_trigger" > "$T/sys/class/leds/led:$n/trigger"
    done
    for n in ${5:-}; do echo "[none] $(echo "$n" | tr -d _)_trigger flash0_trigger" > "$T/sys/class/leds/led:$n/trigger"; done
    echo "$1" > "$T/sys/class/leds/led:switch_2/brightness"
    cat > "$T/drv.sh" <<DRV
HERALD_TORCH_SYSROOT=$T/sys
HERALD_TORCH_DIR=$T/st
getprop() { [ "\$1" = "$2" ] && echo "$3"; return 0; }
blog() { echo "BLOG: \$*"; }
. $P
herald_torch_w() {
  echo "\$2" > "\$TORCH_LED/led:\$1/brightness"; echo "\$1=\$2" >> $T/writes
  [ "\$2" = 0 ] && [ -f "\$TORCH_LED/led:\$1/trigger" ] && echo "[none] \$(echo "\$1" | tr -d _)_trigger" > "\$TORCH_LED/led:\$1/trigger"
  return 0
}
rm -f $T/writes
st() { printf '%s\\n' "\$1" > $T/st/torch_state.tmp; mv $T/st/torch_state.tmp $T/st/torch_state; }
$4
echo "WRITES: \$(cat $T/writes 2>/dev/null | tr '\n' ' ')"
echo "TRIG: \$(for n in torch_0 torch_3 switch_2; do herald_torch_trig \$n; done | tr '\n' ' ')"
DRV
    $SH "$T/drv.sh" 2>&1
  }
  OK="TRIG: torch0_trigger torch3_trigger switch2_trigger "    # 全挂着(开机默认 / 相机占用)
  T3="TRIG: torch0_trigger none switch2_trigger "              # 没 park 时开单颗:torch_3=0 摘掉的不再挂回(下次关灯会 park)
  PK="TRIG: none none switch2_trigger "                        # park:关灯后 torch0 / torch3 故意摘掉
  PARK='for n in torch_0 torch_3; do echo "[none] $(echo $n | tr -d _)_trigger" > $TORCH_LED/led:$n/trigger; done'
  o=$(run 1 - - 'heraldp_cmd_torch "apply 3"')
  eq 单颗默认 "$o" "ok torch level=3 leds=1 ma=200
WRITES: switch_2=0 torch_0=200 torch_3=200 switch_2=1 torch_3=0 torch_0=400 
$T3"
  o=$(run 1 - - 'heraldp_cmd_torch "apply 4"')
  eq 两颗默认 "$o" "ok torch level=4 leds=2 ma=300
WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 
$OK"
  o=$(run 0 - - 'heraldp_cmd_torch "apply 2"')
  eq 已关灯不动 "$o" "ok torch off(手电筒没开,不改)
WRITES: 
$OK"
  o=$(run 1 persist.tb321fu.torch.l1 2x80 'heraldp_cmd_torch "apply 1"')
  eq 自定义档位 "$o" "ok torch level=1 leds=2 ma=80
WRITES: switch_2=0 torch_0=80 torch_3=80 switch_2=1 
$OK"
  o=$(run 1 persist.tb321fu.torch.l4 2x900 'heraldp_cmd_torch "apply 4"')
  eq 上限500 "$o" "ok torch level=4 leds=2 ma=500
WRITES: switch_2=0 torch_0=500 torch_3=500 switch_2=1 
$OK"
  o=$(run 1 persist.tb321fu.torch.l2 abc 'heraldp_cmd_torch "apply 2"')
  eq 坏配置回默认 "$o" "ok torch level=2 leds=1 ma=100
WRITES: switch_2=0 torch_0=100 torch_3=100 switch_2=1 torch_3=0 torch_0=200 
$T3"
  o=$(run 1 persist.tb321fu.torch.l3 1x400 'heraldp_cmd_torch "apply 3"')
  eq 单颗上限250 "$o" "ok torch level=3 leds=1 ma=250
WRITES: switch_2=0 torch_0=250 torch_3=250 switch_2=1 torch_3=0 torch_0=500 
$T3"
  o=$(run 1 - - 'heraldp_cmd_torch "off"')
  eq 关灯时灯还亮_补关并park "$o" "ok torch off(补关)
WRITES: switch_2=0 torch_0=25 
$PK"
  o=$(run 0 - - 'heraldp_cmd_torch "off"')
  eq 关灯时已关_不写0只park "$o" "ok torch off
WRITES: torch_0=25 
$PK"
  o=$(run 0 - - 'heraldp_cmd_torch "apply 2"' "switch_2 torch_3")
  eq switch_2被摘_恢复并照做 "$o" "ok torch level=2 leds=1 ma=100
WRITES: switch_2=0 torch_0=100 torch_3=100 switch_2=1 torch_3=0 torch_0=200 
$T3"
  o=$(run 0 - - 'heraldp_cmd_torch "off"' "switch_2")
  eq 关灯时自愈 "$o" "ok torch off
WRITES: torch_0=25 
$PK"
  o=$(run 0 - - 'herald_torch_heal && echo healed' "switch_2")
  eq 自愈只管switch_2 "$o" "healed
WRITES: 
$OK"
  o=$(run 0 - - 'herald_torch_heal || echo none' "torch_0 torch_3")
  eq 自愈不挂回torch "$o" "none
WRITES: 
$PK"
  o=$(run 0 - - 'echo "[none] flash0_trigger" > $TORCH_LED/led:switch_2/trigger; herald_torch_heal || echo none')
  eq 内核没有这个trigger不硬写 "$o" "none
WRITES: 
TRIG: torch0_trigger torch3_trigger none "
  # ---- park / unpark(V1.4) ----
  o=$(run 1 - - 'herald_torch_park || echo busy')
  eq 灯亮着不park "$o" "busy
WRITES: 
$OK"
  o=$(run 0 - - "$PARK; herald_torch_park; herald_torch_parked")
  eq 已park再park只重写预载 "$o" "yes
WRITES: torch_0=25 
$PK"
  o=$(run 0 - - "$PARK; herald_torch_unpark; herald_torch_parked")
  eq unpark全挂回 "$o" "no
WRITES: 
$OK"
  o=$(run 1 - - "$PARK; heraldp_cmd_torch \"apply 1\"")
  eq park时开单颗 "$o" "ok torch level=1 leds=1 ma=50
WRITES: switch_2=0 torch_0=50 torch_3=50 switch_2=1 torch_3=0 torch_0=100 
$PK"
  o=$(run 1 - - "$PARK; heraldp_cmd_torch \"apply 4\"")
  eq park时开两颗 "$o" "ok torch level=4 leds=2 ma=300
WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 
$PK"
  # ---- watcher 的状态文件处理(herald_torch_handle) ----
  o=$(run 1 - - "$PARK; st '5 on 3'; herald_torch_handle")
  eq 状态on单颗 "$o" "WRITES: switch_2=0 torch_0=200 torch_3=200 switch_2=1 torch_3=0 torch_0=400 
$PK"
  o=$(run 1 - - "$PARK; st '5 on 4'; herald_torch_handle; herald_torch_handle; herald_torch_handle")
  eq 同一行只执行一次 "$o" "WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 
$PK"
  o=$(run 1 - - "$PARK; st '5 on 4'; herald_torch_handle; st '6 on 1'; herald_torch_handle")
  eq 换档按最新 "$o" "WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 switch_2=0 torch_0=50 torch_3=50 switch_2=1 torch_3=0 torch_0=100 
$PK"
  o=$(run 0 - - "$PARK; st '6 on 2'; herald_torch_handle")
  eq HAL已关不点灯 "$o" "WRITES: 
$PK"
  o=$(run 0 - - "$PARK; st '6 on 2'; herald_torch_handle" "switch_2")
  eq switch_2被摘时信App "$o" "WRITES: switch_2=0 torch_0=100 torch_3=100 switch_2=1 torch_3=0 torch_0=200 
$PK"
  o=$(run 1 - - "$PARK; st '7 off'; herald_torch_handle")
  eq 状态off灯还亮补关 "$o" "WRITES: switch_2=0 torch_0=25 
$PK"
  o=$(run 0 - - "st '7 off'; herald_torch_handle")
  eq 状态off从全挂着park "$o" "WRITES: torch_0=25 
$PK"
  o=$(run 0 - - "$PARK; st '8 cam'; herald_torch_handle")
  eq 状态cam全挂回 "$o" "WRITES: 
$OK"
  o=$(run 1 - - "st '8 cam'; herald_torch_handle")
  eq 相机开着cam不动灯 "$o" "WRITES: 
$OK"
  o=$(run 0 - - "$PARK; st '8 cam'; herald_torch_handle; st '9 off'; herald_torch_handle")
  eq 相机关闭重新park "$o" "WRITES: torch_0=25 
$PK"
  o=$(run 1 - - 'for l in "x on 3" "8 on 9" "8 on 3 4" "8 off now" "8 cam 1" "8" "" "8 on"; do st "$l"; herald_torch_handle; done')
  eq 坏状态一律不动 "$o" "WRITES: 
$OK"
  o=$(run 1 - - 'echo "9 on 4" > $HERALD_TORCH_DIR/real; ln -s real $HERALD_TORCH_DIR/torch_state; herald_torch_handle')
  eq 状态是符号链接不读 "$o" "WRITES: 
$OK"
  o=$(run 1 - - 'printf "10 on 4" > $HERALD_TORCH_DIR/torch_state; herald_torch_handle')
  eq 没有换行也认 "$o" "WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 
$OK"
  o=$(run 1 persist.tb321fu.torch.l2 2x120 'st "11 on 2"; herald_torch_handle')
  eq 状态on读档位表 "$o" "WRITES: switch_2=0 torch_0=120 torch_3=120 switch_2=1 
$OK"
  o=$(run 1 - - 'herald_torch_dirok && echo ok || echo bad')
  eq 目录属主不是App不监听 "$o" "bad
WRITES: 
$OK"
  o=$(run 1 - - 'heraldp_cmd_torch "apply 5"')
  eq 档位越界 "$o" "err torch 档位只能是 1~4: [5]
WRITES: 
$OK"
done
echo "通过 $pass 项, 失败 $fail 项"
[ $fail = 0 ]
