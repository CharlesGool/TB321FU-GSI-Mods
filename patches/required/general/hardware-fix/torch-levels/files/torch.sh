# torch-levels 的 broker 插件(装在 /system/etc/herald_payload/plugins/torch.sh,由 herald-start.sh source)。
# 手电筒档位:vendor 相机 HAL(QTI CamX)声明 4 档,但下发给内核的永远是 torch_0=150、torch_3=0(两颗灯各 75 mA),
#   而且亮着时改档会把第二颗灯关掉(驱动清了使能位不再恢复)。这里由 root 按档位重写 PMIC 闪光灯节点。
# 触发:内置 App(com.lenovo.tb321fu.torch,常驻)监听 TorchCallback,手电筒打开 / 改档后经 herald-apps 发 `torch apply <档>`。
# 写法(2026-11-09 真机 kprobe 抓 PMIC 寄存器验证):
#   两颗各 X mA:switch_2=0 → torch_0=X、torch_3=X → switch_2=1
#   单颗 X mA:  先按两颗各 X 打开,再 torch_3=0,再 torch_0=2X
#               (驱动对称配置:单颗时写进 torch_0 的值会平分到两路,只拿到一半;V1.1 真机实测 1~3 档只有 25/50/100 mA)
#   必须先写两路电流再开 switch:switch_2=0 会把两路电流清零,单独再写 1 不会恢复。
# 档位表:persist.tb321fu.torch.l1 … l4,写成 <颗数>x<mA>(两颗 25~500,单颗 25~250);默认 1x50 1x100 1x200 2x300。
# 关灯:`torch off` 只在灯还亮着时写 switch_2=0(HAL 自己的关灯正常就已经关了)。App 收到关灯就发,
#   保证此前在路上的 apply 不会把灯重新点亮。
# ★ trigger(V1.2,test-v2.7 真机证实):相机 HAL 经内核 LED trigger(torch0_trigger / torch3_trigger / switch2_trigger)
#   控制这三个节点。经 sysfs 往 brightness 写 0,内核会把这个 LED 的 trigger 摘掉(brightness_store → led_trigger_remove),
#   之后 HAL 再也开不了灯,只能重启。所以:每次写 0 之后都把 trigger 挂回去(herald_torch_heal);
#   每条 torch 命令开头和 herald 启动时也检查一遍,哪里漏了下一次操作就能自己恢复。
#   只挂回 [none] 的(不动别的 trigger),trigger 名字必须在内核列出的可选项里。
TORCH_LED=${HERALD_TORCH_SYSROOT:-/sys}/class/leds
herald_torch_w() { echo "$2" > "$TORCH_LED/led:$1/brightness" 2>/dev/null; }
herald_torch_heal() {   # 把被摘掉的 trigger 挂回去;挂回过至少一个就返回 0
  _thr=1
  for _thn in torch_0 torch_3 switch_2; do
    _thf=$TORCH_LED/led:$_thn/trigger
    [ -f "$_thf" ] || continue
    _tht=; IFS= read -r _tht < "$_thf" 2>/dev/null
    case "$_tht" in *"[none]"*) ;; *) continue ;; esac
    _thw=${_thn%_*}${_thn#*_}_trigger          # torch_0 → torch0_trigger
    case " $_tht " in *" $_thw "*) ;; *) continue ;; esac
    echo "$_thw" > "$_thf" 2>/dev/null && _thr=0
  done
  return $_thr
}
herald_torch_trig() { _ttt=; IFS= read -r _ttt < "$TORCH_LED/led:$1/trigger" 2>/dev/null; _ttt=${_ttt#*\[}; echo "${_ttt%%]*}"; }
herald_torch_r() { _tv=; IFS= read -r _tv < "$TORCH_LED/led:$1/brightness" 2>/dev/null; echo "$_tv"; }
herald_torch_level() {   # $1 档 → "颗数 mA"
  case "$1" in 1) _td=1x50 ;; 2) _td=1x100 ;; 3) _td=1x200 ;; 4) _td=2x300 ;; *) return 1 ;; esac
  _tl=$(getprop "persist.tb321fu.torch.l$1" 2>/dev/null)
  case "$_tl" in [12]x[0-9]*) ;; *) _tl=$_td ;; esac
  _tn=${_tl%%x*}; _tm=${_tl#*x}
  case "$_tm" in ""|*[!0-9]*) _tn=${_td%%x*}; _tm=${_td#*x} ;; esac
  [ "$_tm" -lt 25 ] && _tm=25
  [ "$_tm" -gt 500 ] && _tm=500
  [ "$_tn" = 1 ] && [ "$_tm" -gt 250 ] && _tm=250     # 单颗要写 2X,节点上限 500
  echo "$_tn $_tm"
}
herald_torch_apply() {   # $1 档 1~4
  _ls=$(herald_torch_level "$1") || { echo "err torch 档位只能是 1~4: [$1]"; return; }
  set -- "$1" $_ls
  [ -e "$TORCH_LED/led:switch_2/brightness" ] || { echo "err torch 没有 $TORCH_LED/led:switch_2"; return; }
  # 手电筒已经关了就不动(否则 switch_2=1 会把灯重新点亮):App 发请求和用户关灯之间可能有先后。
  # 例外:刚挂回过 trigger,说明 HAL 的开灯可能没送到 switch_2,switch_2 不可信;App 只在它认为灯亮着时才发 apply,照做。
  _tfix=""; herald_torch_heal && _tfix=" (trigger 已恢复)"
  if [ -z "$_tfix" ]; then
    case "$(herald_torch_r switch_2)" in ""|0) echo "ok torch off(手电筒没开,不改)"; return ;; esac
  fi
  herald_torch_w switch_2 0
  herald_torch_w torch_0 "$3"
  herald_torch_w torch_3 "$3"
  herald_torch_w switch_2 1
  if [ "$2" = 1 ]; then
    herald_torch_w torch_3 0
    herald_torch_w torch_0 $(($3 * 2))
  fi
  herald_torch_heal       # switch_2=0、torch_3=0 摘掉的 trigger 挂回去,HAL 之后才关得了灯
  echo "ok torch level=$1 leds=$2 ma=$3$_tfix"
}
herald_torch_off() {
  [ -e "$TORCH_LED/led:switch_2/brightness" ] || { echo "err torch 没有 $TORCH_LED/led:switch_2"; return; }
  _tfix=""; herald_torch_heal && _tfix=" (trigger 已恢复)"
  case "$(herald_torch_r switch_2)" in
    ""|0) echo "ok torch off$_tfix" ;;
    *)    herald_torch_w switch_2 0; herald_torch_heal; echo "ok torch off(补关)$_tfix" ;;
  esac
}
herald_torch_boot() { herald_torch_heal && blog "torch: 开机时 trigger 不全,已挂回"; return 0; }
HERALDP_START="${HERALDP_START:-} herald_torch_boot"
heraldp_cmd_torch() {
  set -- $1
  case "$1" in
    apply)  herald_torch_apply "${2:-}" ;;
    off)    herald_torch_off ;;
    status) echo "ok torch"
            for _tn in switch_2 torch_0 torch_3 flash_0 flash_3; do echo "$_tn=$(herald_torch_r $_tn)"; done
            for _tn in switch_2 torch_0 torch_3; do echo "trigger_$_tn=$(herald_torch_trig $_tn)"; done
            for _tn in 1 2 3 4; do echo "l$_tn=$(herald_torch_level $_tn | tr ' ' x)"; done ;;
    *)      echo "err torch 用法: torch apply <1-4> | torch off | torch status" ;;
  esac
}
