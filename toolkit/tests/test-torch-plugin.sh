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
  run() {   # run <switch_2 初值> <属性名> <属性值> <命令>:输出命令回包 + 写入日志
    rm -rf "$T/sys"; for n in switch_2 torch_0 torch_3 flash_0 flash_3; do mkdir -p "$T/sys/class/leds/led:$n"; done
    echo "$1" > "$T/sys/class/leds/led:switch_2/brightness"
    cat > "$T/drv.sh" <<DRV
HERALD_TORCH_SYSROOT=$T/sys
getprop() { [ "\$1" = "$2" ] && echo "$3"; return 0; }
. $P
herald_torch_w() { echo "\$2" > "\$TORCH_LED/led:\$1/brightness"; echo "\$1=\$2" >> $T/writes; }
rm -f $T/writes
$4
echo "WRITES: \$(cat $T/writes 2>/dev/null | tr '\n' ' ')"
DRV
    $SH "$T/drv.sh" 2>&1
  }
  o=$(run 1 - - 'heraldp_cmd_torch "apply 3"')
  eq 单颗默认 "$o" "ok torch level=3 leds=1 ma=200
WRITES: switch_2=0 torch_0=200 torch_3=200 switch_2=1 torch_3=0 torch_0=400 "
  o=$(run 1 - - 'heraldp_cmd_torch "apply 4"')
  eq 两颗默认 "$o" "ok torch level=4 leds=2 ma=300
WRITES: switch_2=0 torch_0=300 torch_3=300 switch_2=1 "
  o=$(run 0 - - 'heraldp_cmd_torch "apply 2"')
  eq 已关灯不动 "$o" "ok torch off(手电筒没开,不改)
WRITES: "
  o=$(run 1 persist.tb321fu.torch.l1 2x80 'heraldp_cmd_torch "apply 1"')
  eq 自定义档位 "$o" "ok torch level=1 leds=2 ma=80
WRITES: switch_2=0 torch_0=80 torch_3=80 switch_2=1 "
  o=$(run 1 persist.tb321fu.torch.l4 2x900 'heraldp_cmd_torch "apply 4"')
  eq 上限500 "$o" "ok torch level=4 leds=2 ma=500
WRITES: switch_2=0 torch_0=500 torch_3=500 switch_2=1 "
  o=$(run 1 persist.tb321fu.torch.l2 abc 'heraldp_cmd_torch "apply 2"')
  eq 坏配置回默认 "$o" "ok torch level=2 leds=1 ma=100
WRITES: switch_2=0 torch_0=100 torch_3=100 switch_2=1 torch_3=0 torch_0=200 "
  o=$(run 1 persist.tb321fu.torch.l3 1x400 'heraldp_cmd_torch "apply 3"')
  eq 单颗上限250 "$o" "ok torch level=3 leds=1 ma=250
WRITES: switch_2=0 torch_0=250 torch_3=250 switch_2=1 torch_3=0 torch_0=500 "
  o=$(run 1 - - 'heraldp_cmd_torch "off"')
  eq 关灯 "$o" "ok torch off
WRITES: switch_2=0 "
  o=$(run 1 - - 'heraldp_cmd_torch "apply 5"')
  eq 档位越界 "$o" "err torch 档位只能是 1~4: [5]
WRITES: "
done
echo "通过 $pass 项, 失败 $fail 项"
[ $fail = 0 ]
