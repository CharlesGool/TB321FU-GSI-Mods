# torch-levels:手电筒档位

## 现象

下拉面板长按"手电筒"出来的亮度滑块拖了没用:刚打开最亮,一拖就变暗,之后 1~4 档都一样暗;关掉再直接点开又恢复。

## 原因(DP11 test-v2.5 真机,kprobe 抓 PMIC 闪光灯模块 pm8550 `flash_led@ee00` 的寄存器写入)

1. **vendor 相机 HAL(QTI CamX)忽略档位**:声明 `strengthMaximumLevel=4`,但不管设哪档,下发给内核的都是 `torch_0=150, torch_3=0, switch_2=1`。
   驱动把 150 mA 对称分到两路,两颗灯各 75 mA(每路硬件上限 500 mA)。
2. **亮着时改档会关掉第二颗灯**:每次都写 `torch_3=0`,`qti_flash` 驱动清掉通道 3 的使能位(`0xEE4E` bit3);
   从灭到亮时 `switch_2=1` 会重写使能,亮着时不会,于是只剩一颗。

## 做法(不改 vendor)

```
CameraService ──TorchCallback──▶ TB321FU-Torch App(persistent、directBootAware)
                                   │ 只维护一份"最新期望状态": <seq> on <档> | <seq> off
                                   │ 每次变化:写 torch_state.tmp → rename 成 torch_state(原子)
                                   ▼
               /data/user_de/0/com.lenovo.tb321fu.torch/files/torch_state
                                   │ inotify
                                   ▼
herald torch watcher(HERALDP_START 起的常驻子进程)
   每个事件:读最新一行 → 和上次处理过的一样就跳过 → 否则 apply / off(全是 shell 内建,0 次 fork)
```

- **为什么不走 herald-apps**(V1.3):请求→回包一次往返 0.35~0.57 秒(约 40 次 fork),请求排队、过时执行,
  test-v2.8 上出现过"快拖 → 关 → 立刻再开,约 1.5 秒后灯被旧的 off 关掉"。现在 App 不等回包,watcher 只执行最新一行,
  过时状态结构上不可能执行。原型实测改档 21~51 ms 到目标电流,HAL 那下 75 mA 只剩 20~40 ms。
- **App**:监听 `TorchCallback`;每次打开都换一个 seq(HAL 开灯总是先写自己的 75+75,同档位也要重写);
  LEVEL 回调会丢(刚打开后的第一次改档、有时整段拖动),所以灯亮着时每 150 ms 读一次 `getTorchStrengthLevel()` 兜底。
  直接点开 = 跟随 `getTorchStrengthLevel()`(当前 HAL 报 4 档),和下拉面板滑块显示一致。
  `cameraserver` 不能 binder 回调到 herald 域,所以监听必须留在普通 App 里。
- **herald 插件** `files/torch.sh`(写法都在真机上用 root 写 sysfs、抓寄存器验证过):
  - 两颗各 X mA:`switch_2=0` → `torch_0=X`、`torch_3=X` → `switch_2=1`;
  - 单颗 X mA:再 `torch_3=0`、`torch_0=2X`(驱动对称配置,单颗时写进 `torch_0` 的值只拿到一半;单颗最大 250 mA);
  - 点灯前确认 HAL 还亮着(`switch_2=1`),挡掉"关灯瞬间轮询读到复位后的档位";
  - 关灯正常由 HAL 自己关;收到 off 时只有 `switch_2` 仍为 1 才补写 0。
- **LED trigger(V1.2)**:相机 HAL 经内核 LED trigger(`torch0_trigger` / `torch3_trigger` / `switch2_trigger`)控制这三个节点。
  经 sysfs 往 `brightness` 写 0,内核会把这个 LED 的 trigger 摘掉,HAL 之后再也开不了灯(test-v2.7 实测)。
  所以每次写 0 后把 `[none]` 挂回去(挂回不改亮度,test-v2.8 kprobe 确认);每次 apply / off 和 watcher 启动时也检查一遍。
  刚挂回过 trigger 时 `switch_2` 不可信,点灯改为信 App。
- **鉴权**:状态文件里只认 `数字 on 1-4` / `数字 off`,写进 sysfs 的值只来自档位表,伪造也只能开关手电筒;
  文件在包自己的 DE 数据目录里,只有包的 uid 能写;watcher 每次(重)建监听时核对目录属主(≥10000、不是符号链接)。
- 档位表(默认):1 档单颗 50 mA、2 档单颗 100 mA、3 档单颗 200 mA、4 档两颗各 300 mA。
  可改:`setprop persist.tb321fu.torch.l<档> <颗数>x<mA>`(颗数 1 / 2,mA 25~500);watcher 每次关灯后重读,下次开灯生效。

## 风险

- 4 档两颗各 300 mA(原厂两颗各 75)明显更热,长时间开着要留意温度;vendor HAL 的 `cam-flash-therm` 温控对 sysfs 写入是否还会接管,未验证。
- 每次打开 / 改档,先以 HAL 的值亮一下(V1.3 原型实测 20~40 ms),再变成这里的值。
- V1.0(test-v2.6)的问题:关灯后已在路上的 apply 把灯重新点亮;单颗电流只有设定值的一半;改档后约 1 秒才生效。V1.1 修。
- V1.1(test-v2.7)的问题:写 0 摘掉了 HAL 的 trigger,手电筒坏到重启;重启后首次解锁前 App 不运行。V1.2 修。
- V1.2(test-v2.8)的问题:herald-apps 请求通道慢且排队,过时的 off 把新开的灯关掉;LEVEL 回调丢失时档位不变。V1.3 改成状态文件 + inotify,App 轮询档位兜底。

## 验证

```bash
adb shell 'ush -c "heraldctl raw torch status"'          # bebug:看 switch_2 / torch_0 / torch_3、trigger、档位表、当前状态文件
adb logcat -s TB321FU-Torch                              # 打开、拖滑块、关灯时有 "state <seq> on N (on|level|poll)" / "state <seq> off"
```
体感:1→3 档逐档变亮且只有一颗灯亮,4 档两颗都亮;亮着拖滑块不再变暗。
**trigger 必须一直在**(反复开关、拖档、穿插相机之后):
```bash
for l in torch_0 torch_3 switch_2; do grep -o '\[[^]]*\]' /sys/class/leds/led:$l/trigger; done   # [torch0_trigger] [torch3_trigger] [switch2_trigger]
```
**关灯后 5 秒内 `cat /sys/class/leds/led:switch_2/brightness` 必须是 0**,灯必须是灭的。
精确核对用 kprobe `regmap_update_bits_base`(reg 0xee00~0xeeff):`0xEE42 / 0xEE45` 电流码 = mA / 12.5 − 1,`0xEE4E` 4 档时保持 0x9。

源码在 `app/`(`app/build-linux.sh`);签名 key 在 `app/keystore/`,不进仓库。
