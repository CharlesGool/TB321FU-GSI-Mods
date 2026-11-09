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
    rm -rf "$T/sys"; for n in switch_2 torch_0 torch_3 flash_0 flash_3; do mkdir -p "$T/sys/class/leds/led:$n"; done
    for n in torch_0 torch_3 switch_2; do   # 假 trigger 文件:当前项带 [],写 0 时(模拟内核)换成 [none]
      echo "none [$(echo "$n" | tr -d _)_trigger] flash0_trigger" > "$T/sys/class/leds/led:$n/trigger"
    done
    for n in ${5:-}; do echo "[none] $(echo "$n" | tr -d _)_trigger flash0_trigger" > "$T/sys/class/leds/led:$n/trigger"; done
    echo "$1" > "$T/sys/class/leds/led:switch_2/brightness"
    cat > "$T/drv.sh" <<DRV
HERALD_TORCH_SYSROOT=$T/sys
getprop() { [ "\$1" = "$2" ] && echo "$3"; return 0; }
blog() { echo "BLOG: \$*"; }
. $P
herald_torch_w() {
  echo "\$2" > "\$TORCH_LED/led:\$1/brightness"; echo "\$1=\$2" >> $T/writes
  [ "\$2" = 0 ] && [ -f "\$TORCH_LED/led:\$1/trigger" ] && echo "[none] \$(echo "\$1" | tr -d _)_trigger" > "\$TORCH_LED/led:\$1/trigger"
  return 0
}
rm -f $T/writes
$4
echo "WRITES: \$(cat $T/writes 2>/dev/null | tr '\n' ' ')"
echo "TRIG: \$(for n in torch_0 torch_3 switch_2; do herald_torch_trig \$n; done | tr '\n' ' ')"
DRV
    $SH "$T/drv.sh" 2>&1
  }
  OK="TRIG: torch0_trigger torch3_trigger switch2_trigger "
  o=$(run 1 - - 'heraldp_cmd_torch "apply 3"')
  eq 单颗默认 "$o" "ok torch level=3 leds=1 ma=200
WRITES: switch_2=0 torch_0=200 torch_3=200 switch_2=1 torch_3=0 torch_0=400 
$OK"
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
$OK"
  o=$(run 1 persist.tb321fu.torch.l3 1x400 'heraldp_cmd_torch "apply 3"')
  eq 单颗上限250 "$o" "ok torch level=3 leds=1 ma=250
WRITES: switch_2=0 torch_0=250 torch_3=250 switch_2=1 torch_3=0 torch_0=500 
$OK"
  o=$(run 1 - - 'heraldp_cmd_torch "off"')
  eq 关灯时灯还亮_补关并挂回 "$o" "ok torch off(补关)
WRITES: switch_2=0 
$OK"
  o=$(run 0 - - 'heraldp_cmd_torch "off"')
  eq 关灯时已关_不写0 "$o" "ok torch off
WRITES: 
$OK"
  o=$(run 0 - - 'heraldp_cmd_torch "apply 2"' "switch_2 torch_3")
  eq trigger被摘_恢复并照做 "$o" "ok torch level=2 leds=1 ma=100 (trigger 已恢复)
WRITES: switch_2=0 torch_0=100 torch_3=100 switch_2=1 torch_3=0 torch_0=200 
$OK"
  o=$(run 0 - - 'heraldp_cmd_torch "off"' "switch_2")
  eq 关灯时自愈 "$o" "ok torch off (trigger 已恢复)
WRITES: 
$OK"
  o=$(run 0 - - 'herald_torch_boot' "torch_3")
  eq 开机自愈 "$o" "BLOG: torch: 开机时 trigger 不全,已挂回
WRITES: 
$OK"
  o=$(run 0 - - 'echo "[none] flash0_trigger" > $TORCH_LED/led:torch_3/trigger; herald_torch_boot')
  eq 内核没有这个trigger不硬写 "$o" "WRITES: 
TRIG: torch0_trigger none switch2_trigger "
  o=$(run 0 - - 'herald_torch_boot')
  eq 开机正常不写 "$o" "WRITES: 
$OK"
  o=$(run 1 - - 'heraldp_cmd_torch "apply 5"')
  eq 档位越界 "$o" "err torch 档位只能是 1~4: [5]
WRITES: 
$OK"
done
echo "通过 $pass 项, 失败 $fail 项"
[ $fail = 0 ]
