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
# 关灯:`torch off` 写 switch_2=0(会把两路电流清零)。App 收到关灯就发,保证此前在路上的 apply 不会把灯重新点亮。
TORCH_LED=${HERALD_TORCH_SYSROOT:-/sys}/class/leds
herald_torch_w() { echo "$2" > "$TORCH_LED/led:$1/brightness" 2>/dev/null; }
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
  # 手电筒已经关了就不动(否则 switch_2=1 会把灯重新点亮):App 发请求和用户关灯之间可能有先后
  case "$(herald_torch_r switch_2)" in ""|0) echo "ok torch off(手电筒没开,不改)"; return ;; esac
  herald_torch_w switch_2 0
  herald_torch_w torch_0 "$3"
  herald_torch_w torch_3 "$3"
  herald_torch_w switch_2 1
  if [ "$2" = 1 ]; then
    herald_torch_w torch_3 0
    herald_torch_w torch_0 $(($3 * 2))
  fi
  echo "ok torch level=$1 leds=$2 ma=$3"
}
herald_torch_off() {
  [ -e "$TORCH_LED/led:switch_2/brightness" ] || { echo "err torch 没有 $TORCH_LED/led:switch_2"; return; }
  herald_torch_w switch_2 0
  echo "ok torch off"
}
heraldp_cmd_torch() {
  set -- $1
  case "$1" in
    apply)  herald_torch_apply "${2:-}" ;;
    off)    herald_torch_off ;;
    status) echo "ok torch"
            for _tn in switch_2 torch_0 torch_3 flash_0 flash_3; do echo "$_tn=$(herald_torch_r $_tn)"; done
            for _tn in 1 2 3 4; do echo "l$_tn=$(herald_torch_level $_tn | tr ' ' x)"; done ;;
    *)      echo "err torch 用法: torch apply <1-4> | torch off | torch status" ;;
  esac
}
