# torch-levels:手电筒档位

## 现象

下拉面板长按"手电筒"出来的亮度滑块拖了没用:刚打开最亮,一拖就变暗,之后 1~4 档都一样暗;关掉再直接点开又恢复。

## 原因(DP11 test-v2.5 真机,kprobe 抓 PMIC 闪光灯模块 pm8550 `flash_led@ee00` 的寄存器写入)

1. **vendor 相机 HAL(QTI CamX)忽略档位**:声明 `strengthMaximumLevel=4`,但不管设哪档,下发给内核的都是 `torch_0=150, torch_3=0, switch_2=1`。
   驱动把 150 mA 对称分到两路,两颗灯各 75 mA(每路硬件上限 500 mA)。
2. **亮着时改档会关掉第二颗灯**:每次都写 `torch_3=0`,`qti_flash` 驱动清掉通道 3 的使能位(`0xEE4E` bit3);
   从灭到亮时 `switch_2=1` 会重写使能,亮着时不会,于是只剩一颗。

## 做法(不改 vendor)

- **herald 插件** `files/torch.sh`:`torch apply <1-4>` 按档位表重写节点(都在真机上用 root 写 sysfs、抓寄存器验证过):
  - 两颗各 X mA:`switch_2=0` → `torch_0=X`、`torch_3=X` → `switch_2=1`;
  - 单颗 X mA:先按两颗各 X 打开,再 `torch_3=0`,再 `torch_0=2X`(驱动对称配置,单颗时写进 `torch_0` 的值只拿到一半;单颗最大 250 mA);
  - 必须先写两路电流再开 switch(`switch_2=0` 会把两路电流清零,单独再写 1 不恢复);手电筒已经关了就不动。
- **关灯**:正常由 HAL 自己关;`torch off` 只在灯还亮着时补写 `switch_2=0`(防在路上的 apply 把灯重新点亮)。
- **LED trigger(V1.2)**:相机 HAL 经内核 LED trigger(`torch0_trigger` / `torch3_trigger` / `switch2_trigger`)控制这三个节点。
  经 sysfs 往 `brightness` 写 0,内核会把这个 LED 的 trigger 摘掉(`brightness_store` → `led_trigger_remove`),HAL 之后再也开不了灯,只能重启(test-v2.7 实测)。
  所以插件每次写 0 之后都把 trigger 挂回去;每条 `torch` 命令开头和 herald 启动时也检查一遍,是 `[none]` 就挂回(只挂内核列出的那个名字,不动别的 trigger)。
  apply 时如果刚挂回过 trigger,`switch_2` 不可信(HAL 的开灯可能没送到),照 App 的请求点亮(App 只在它认为灯亮着时发 apply)。
- **常驻小 App** `com.lenovo.tb321fu.torch`(没有界面和入口,`persistent`、`directBootAware`):`TorchCallback` 收到"打开"立刻发、"改档"防抖 40 ms,
  经 herald-apps 发 `torch apply <档>`;收到"关灯"就丢掉还没发的改档,并在写过灯的情况下发 `torch off`(白名单只有这两条)。
  发给 herald 的请求在单独一条线程上按顺序排队,`off` 一定排在之前的 `apply` 后面:已经在路上的 apply 不会在关灯后把灯重新点亮(V1.0 的 bug)。
  HAL 每次改档都会先写回 150/0(单颗 75 mA),App 的请求在它之后才到,最终是这里的值。
  直接点开(不选档位)时按 HAL 报的档位处理;HAL 报不出来(<1)时用相机声明的默认档。
  App 和 herald 的通道放在设备加密(DE)存储里:重启后还没解锁时(锁屏下拉面板开手电筒)档位也生效。
- 档位表(默认):1 档单颗 50 mA、2 档单颗 100 mA、3 档单颗 200 mA、4 档两颗各 300 mA。
  可改:`setprop persist.tb321fu.torch.l<档> <颗数>x<mA>`(颗数 1 / 2,mA 25~500),下次改档生效。

## 风险

- 4 档两颗各 300 mA(原厂两颗各 75)明显更热,长时间开着要留意温度;vendor HAL 的 `cam-flash-therm` 温控对 sysfs 写入是否还会接管,未验证。
- 每次打开 / 改档,先以 HAL 的值亮一下,再变成这里的值(test-v2.7 实测 0.5~0.75 秒;V1.2 缩短了 App 和 herald-apps 的等待)。
- 挂回 trigger 时内核会不会顺手按 trigger 上次的值改亮度,取决于内核版本;按 HAL 状态推算无害,要用 kprobe 确认。
- V1.0(test-v2.6)的问题:关灯后已在路上的 apply 把灯重新点亮;单颗电流只有设定值的一半;改档后约 1 秒才生效。V1.1 修。
- V1.1(test-v2.7)的问题:写 0 摘掉了 HAL 的 trigger,手电筒坏到重启;重启后首次解锁前 App 不运行。V1.2 修。

## 验证

```bash
adb shell 'ush -c "heraldctl raw torch status"'          # 或 heraldctl 命令行;看 switch_2 / torch_0 / torch_3 和档位表
adb logcat -s TB321FU-Torch                              # 打开、拖滑块时有 "ok torch level=N leds=… ma=…"
```
体感:1→3 档逐档变亮且只有一颗灯亮,4 档两颗都亮;亮着拖滑块不再变暗。
**trigger 必须一直在**(反复开关、拖档、穿插相机之后):
```bash
for l in torch_0 torch_3 switch_2; do grep -o '\[[^]]*\]' /sys/class/leds/led:$l/trigger; done   # [torch0_trigger] [torch3_trigger] [switch2_trigger]
```
**关灯后 5 秒内 `cat /sys/class/leds/led:switch_2/brightness` 必须是 0**,灯必须是灭的。
精确核对用 kprobe `regmap_update_bits_base`(reg 0xee00~0xeeff):`0xEE42 / 0xEE45` 电流码 = mA / 12.5 − 1,`0xEE4E` 4 档时保持 0x9。

源码在 `app/`(`app/build-linux.sh`);签名 key 在 `app/keystore/`,不进仓库。
