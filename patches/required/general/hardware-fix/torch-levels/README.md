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
  - 单颗 X mA:先按两颗各 X 打开,再 `torch_3=0`(通道 0 保持 X);
  - 必须先写两路电流再开 switch(`switch_2=0` 会把两路电流清零,单独再写 1 不恢复);手电筒已经关了就不动。
- **常驻小 App** `com.lenovo.tb321fu.torch`(没有界面和入口,`persistent`):`TorchCallback` 收到"打开"或"改档"后防抖 250 ms,
  经 herald-apps 发 `torch apply <档>`(白名单只有这一条)。HAL 每次改档都会先写回 150/0,App 的请求在它之后到,所以最终是这里的值。
  直接点开(不调档)按 HAL 的默认档(3)处理。
- 档位表(默认):1 档单颗 50 mA、2 档单颗 100 mA、3 档单颗 200 mA、4 档两颗各 300 mA。
  可改:`setprop persist.tb321fu.torch.l<档> <颗数>x<mA>`(颗数 1 / 2,mA 25~500),下次改档生效。

## 风险

- 4 档两颗各 300 mA(原厂两颗各 75)明显更热,长时间开着要留意温度;vendor HAL 的 `cam-flash-therm` 温控对 sysfs 写入是否还会接管,未验证。
- 直接点开会先以原厂的 2 x 75 mA 亮一下(约几百毫秒),再变成 3 档的值。

## 验证

```bash
adb shell 'ush -c "heraldctl raw torch status"'          # 或 heraldctl 命令行;看 switch_2 / torch_0 / torch_3 和档位表
adb logcat -s TB321FU-Torch                              # 打开、拖滑块时有 "ok torch level=N leds=… ma=…"
```
体感:1→3 档逐档变亮且只有一颗灯亮,4 档两颗都亮;亮着拖滑块不再变暗。
精确核对用 kprobe `regmap_update_bits_base`(reg 0xee00~0xeeff):`0xEE42 / 0xEE45` 电流码 = mA / 12.5 − 1,`0xEE4E` 4 档时保持 0x9。

源码在 `app/`(`app/build-linux.sh`);签名 key 在 `app/keystore/`,不进仓库。
