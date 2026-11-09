# torch-levels 的 herald 插件(装在 /system/etc/herald_payload/plugins/torch.sh,由 herald-start.sh source)。
# 手电筒档位:vendor 相机 HAL(QTI CamX)声明 4 档,但下发给内核的永远是 torch_0=150、torch_3=0(两颗灯各 75 mA),
#   而且亮着时改档会把第二颗灯关掉(驱动清了使能位不再恢复)。这里由 root 按档位重写 PMIC 闪光灯节点。
#
# 通道(V1.3,test-v2.8 上原型验证):内置 App(com.lenovo.tb321fu.torch,常驻、directBootAware)监听 TorchCallback,
#   只维护一份"最新期望状态",原子地写进 /data/user_de/0/<包>/files/torch_state:`<seq> on <1-4>` 或 `<seq> off`。
#   这里起一个常驻 watcher,inotifyd 一有事件就重读这个文件,和上次处理过的那行一样就跳过,否则 apply / off。
#   不排队、不等回包:过时的状态结构上不可能被执行(V1.0~V1.2 走 herald-apps 请求通道,一次往返 0.35~0.57 s,
#   请求堆积后过时执行,会把新开的灯关掉)。每次事件 0 次 fork(全是 shell 内建),实测收敛 8~51 ms。
#   不走 herald-apps:状态文件里只认 `数字 on 1-4` / `数字 off`,写进 sysfs 的值只来自档位表,伪造也只能开关手电筒;
#   目录在包自己的 DE 数据目录里,只有包的 uid 能写。watcher 每次(重)建监听时核对目录属主(>=10000、不是符号链接)。
#
# 写法(2026-11-09 真机 kprobe 抓 PMIC 寄存器验证):
#   两颗各 X mA:switch_2=0 → torch_0=X、torch_3=X → switch_2=1
#   单颗 X mA:  先按两颗各 X 打开,再 torch_3=0,再 torch_0=2X
#               (驱动对称配置:单颗时写进 torch_0 的值会平分到两路,只拿到一半)
#   必须先写两路电流再开 switch:switch_2=0 会把两路电流清零,单独再写 1 不会恢复。
# 点灯前确认 HAL 还亮着(switch_2=1):挡掉"关灯瞬间 App 轮询读到复位后的档位"和"on 到时 HAL 已经关了"。
# 关灯:正常由 HAL 自己经 switch2_trigger 关;收到 off 时只有 switch_2 仍为 1 才补写 0。
# ★ trigger(V1.2,test-v2.7 真机证实):相机 HAL 经内核 LED trigger(torch0_trigger / torch3_trigger / switch2_trigger)
#   控制这三个节点。经 sysfs 往 brightness 写 0,内核会把这个 LED 的 trigger 摘掉(brightness_store → led_trigger_remove),
#   之后 HAL 再也开不了灯。所以每次写 0 之后都把 [none] 挂回去(herald_torch_heal;挂回不改亮度,test-v2.8 kprobe 确认);
#   每次 apply / off 开头和 watcher 启动时也检查一遍。刚挂回过 trigger 时 switch_2 不可信,点灯改为信 App。
# 档位表:persist.tb321fu.torch.l1 … l4,写成 <颗数>x<mA>(两颗 25~500,单颗 25~250);默认 1x50 1x100 1x200 2x300。
#   watcher 启动时读一次,之后每次关灯后重读(改了属性,下次开灯生效)。
# ★ 函数名不要用 r / w 这类单字母:mksh 自带别名 r='fc -e -',会把函数顶掉。
TORCH_LED=${HERALD_TORCH_SYSROOT:-/sys}/class/leds
TORCH_PKG=com.lenovo.tb321fu.torch
TORCH_DIR=${HERALD_TORCH_DIR:-/data/user_de/0/$TORCH_PKG/files}
herald_torch_w()  { echo "$2" > "$TORCH_LED/led:$1/brightness" 2>/dev/null; }
herald_torch_rd() { _tv=; IFS= read -r _tv < "$TORCH_LED/led:$1/brightness" 2>/dev/null; }
herald_torch_r()  { herald_torch_rd "$1"; echo "$_tv"; }
herald_torch_heal() {   # 把被摘掉的 trigger 挂回去;挂回过至少一个就返回 0(全是内建)
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
herald_torch_loadlv() {   # 档位表读进 TORCH_N<档> / TORCH_M<档>(有 getprop,只在启动和关灯后调)
  for _tli in 1 2 3 4; do
    _tll=$(herald_torch_level "$_tli")
    eval "TORCH_N$_tli=\${_tll% *} TORCH_M$_tli=\${_tll#* }"
  done
}
herald_torch_apply() {   # $1 档 1~4;点了灯返回 0,HAL 已经关了(没点)返回 1
  [ -n "${TORCH_N1:-}" ] || herald_torch_loadlv
  eval "_tn=\$TORCH_N$1 _tm=\$TORCH_M$1"
  _tfix=0; herald_torch_heal && _tfix=1
  herald_torch_rd switch_2
  # HAL 已经关了(更新的 off 马上就到)就不点;刚挂回过 trigger 时 switch_2 不可信,信 App
  [ "$_tfix" = 1 ] || [ "$_tv" = 1 ] || return 1
  herald_torch_w switch_2 0; herald_torch_w torch_0 "$_tm"; herald_torch_w torch_3 "$_tm"; herald_torch_w switch_2 1
  if [ "$_tn" = 1 ]; then herald_torch_w torch_3 0; herald_torch_w torch_0 $((_tm * 2)); fi
  herald_torch_heal       # switch_2=0、torch_3=0 摘掉的 trigger 挂回去,HAL 之后才关得了灯
  return 0
}
herald_torch_off() {     # 补关了返回 0,HAL 已经关了返回 1
  herald_torch_heal
  herald_torch_rd switch_2
  [ "$_tv" = 1 ] || return 1               # 正常情况 HAL 已经关了
  herald_torch_w switch_2 0; herald_torch_heal
  return 0
}
TORCH_LAST=
herald_torch_handle() {   # 读最新状态,和上次处理过的不一样才执行
  _tsf=$TORCH_DIR/torch_state
  [ -f "$_tsf" ] && [ ! -L "$_tsf" ] || return 0
  _ts=; IFS= read -r _ts < "$_tsf" 2>/dev/null || [ -n "$_ts" ] || return 0
  [ "$_ts" = "$TORCH_LAST" ] && return 0
  set -- $_ts
  case "${1:-}" in ""|*[!0-9]*) return 0 ;; esac
  case "${2:-}:${3:-}:${4:-}" in
    on:[1-4]:) TORCH_LAST=$_ts; herald_torch_apply "$3" ;;
    off::)     TORCH_LAST=$_ts; herald_torch_off; herald_torch_loadlv ;;
  esac
  return 0
}
herald_torch_dirok() {   # 每次(重)建监听时:目录不是符号链接,目录和包目录属主一致且是 App 的 uid
  [ -d "$TORCH_DIR" ] && [ ! -L "$TORCH_DIR" ] && [ ! -L "${TORCH_DIR%/*}" ] || return 1
  _tdu=$(stat -c %u "$TORCH_DIR" 2>/dev/null); _tpu=$(stat -c %u "${TORCH_DIR%/*}" 2>/dev/null)
  [ "$_tdu" -ge 10000 ] 2>/dev/null && [ "$_tdu" = "$_tpu" ]
}
herald_torch_watch() {
  herald_torch_heal && blog "torch: 开机时 trigger 不全,已挂回"
  herald_torch_loadlv
  _tbad=0
  while true; do
    if ! herald_torch_dirok; then
      [ -d "$TORCH_DIR" ] && [ $_tbad = 0 ] && { blog "torch: $TORCH_DIR 属主 / 类型不对,不监听"; _tbad=1; }
      sleep 2; continue
    fi
    _tbad=0
    # inotifyd 先起,0.3 s 后补一次 init,防止起监听前的那次写入漏掉。
    # 报的文件名不可靠(rename 的 m 事件报的是 tmp 名),收到任何事件都重读 torch_state。
    { inotifyd - "$TORCH_DIR:mwn" & sleep 0.3; echo init; wait; } 2>/dev/null |
      while read -r _te _td _tf; do herald_torch_handle; done
    sleep 1     # 目录被删(清除数据 / 卸载)时 inotifyd 退出,重建监听
  done
}
herald_torch_start() { ( herald_torch_watch ) & }
HERALDP_START="${HERALDP_START:-} herald_torch_start"
heraldp_cmd_torch() {   # 排查用(heraldctl,bebug):status;apply / off 和 watcher 同一套写法
  set -- $1
  case "$1" in
    apply)  case "${2:-}" in [1-4]) ;; *) echo "err torch 档位只能是 1~4: [${2:-}]"; return ;; esac
            [ -e "$TORCH_LED/led:switch_2/brightness" ] || { echo "err torch 没有 $TORCH_LED/led:switch_2"; return; }
            if herald_torch_apply "$2"; then eval "echo \"ok torch level=$2 leds=\$TORCH_N$2 ma=\$TORCH_M$2\""
            else echo "ok torch off(手电筒没开,不改)"; fi ;;
    off)    if herald_torch_off; then echo "ok torch off(补关)"; else echo "ok torch off"; fi ;;
    status) echo "ok torch"
            for _tn in switch_2 torch_0 torch_3 flash_0 flash_3; do echo "$_tn=$(herald_torch_r $_tn)"; done
            for _tn in switch_2 torch_0 torch_3; do echo "trigger_$_tn=$(herald_torch_trig $_tn)"; done
            for _tn in 1 2 3 4; do echo "l$_tn=$(herald_torch_level $_tn | tr ' ' x)"; done
            _ts=; IFS= read -r _ts < "$TORCH_DIR/torch_state" 2>/dev/null; echo "state=$_ts" ;;
    *)      echo "err torch 用法: torch status | torch apply <1-4> | torch off" ;;
  esac
}
