# cover-rotation-fix:皮套合盖灭屏、开盖亮屏 + 触摸屏边缘防误触跟随旋转

适用于 TB321FU(原厂 ZUI 17.0.12 vendor)上的 Pixel GSI。2026-11-09 在 DP11 user-v1.9 体检时发现,对照原厂 ZUI 17.0.12 反编译核实。

## 问题

| 功能 | 原厂 ZUI 怎么做 | GSI 现状 |
|---|---|---|
| 皮套 | `ZuiPhoneWindowManager` 注册高通 vendor 霍尔传感器 `getDefaultSensor(33171002, true)`(`bu52053nvx Hall Effect Sensor`,wakeup 版),`values[0]==1` 为开盖,再调 `PhoneWindowManager.notifyLidSwitchChanged(now, open)` | 没人注册这个传感器,内核也没有 SW_LID 输入设备,合盖、开盖都没反应 |
| 边缘防误触方向 | `EdgeInhibitionInputPolicy` 每次转屏调触摸 HAL `ITouchscreen.setEdgeInhibition(rotation 0..3)`,HAL 写 `/proc/panel_direction` | 一直是 0(竖屏),横屏时触摸芯片仍按竖屏边缘做防误触 |

## 做法

在 services.jar 里加一个类 `com.android.server.policy.Tb321fuHwPolicy`(`src/`),在 `PhoneWindowManager.systemReady()` 末尾插一行 `Tb321fuHwPolicy.init(mContext, this)`。不改 vendor、不改 sepolicy、不用 herald。

- helper 只引用公开 API(隐藏 API 走反射),用 `ANDROID_JAR` 现编(javac + d8),作为一份新 dex 追加在 services.jar 最后,编号现算(要排在 faceunlock 后面,它固定加 `classes4.dex`)。
- 钩子由 `apply_hook.py` 打在 systemReady 最后一个 `return-void` 前(synchronized 块之外),回编后只换 PhoneWindowManager 所在的那份 dex,并做 smali 等价核对。DP11 的 services.jar 先用 `toolkit/lib/dex041.sh` 拆成标准 multidex。
- 只有 `ro.product.vendor.device=TB321FU` 时才启用;`init()` 和所有回调都包了 try/catch,最坏情况只是功能不生效。
- 合盖:AOSP 收到合盖后按 `Settings.Global lid_behavior` 处理(0 不处理、1 灭屏、2 锁屏),开盖一律 `wakeUpFromLid()` 亮屏。Pixel 默认已经把 `lid_behavior` 写成 0,所以 helper 第一次开机强制写 1,同时写标记 `tb321fu_lid_behavior_init=1`;之后不再改,用户自己改的值会保留。
- 旋转:默认屏旋转变化时,直接对 `vendor.lenovo.hardware.touchscreen.ITouchscreen/default` 发事务 10(`setEdgeInhibition(int)`)。原厂 vendor sepolicy 里 system_server 就是 `hal_lenovotouchscreen_client`,真机已验证 `service call ... 10 i32 1` 返回 1 且 `/proc/panel_direction` 变成 90°。

## 上机验证

DP11 test-v2.0-cust_bebug(2026-11-09):
- helper 正常启动,霍尔 wakeup 传感器(0x3fe)由 Tb321fuHwPolicy 注册,开机读到 1.00(开盖)。
- 旋转一圈:ROTATION_0/90/180/270 依次对应 `/proc/panel_direction` 的 0/90/180/270,1 秒内同步。
- 皮套:`lid_behavior=1` 后连续 4 次合盖灭屏、开盖亮屏,`mLastWakeReason=9`(LID)。
- V1.0 的"没设过才写 1"在 Pixel 上不触发(Pixel 默认已是 0);V1.1 改为第一次开机强制写一次(test-v2.1 起)。

## 可调设置(`adb shell settings put global <key> <value>`,立即生效)

| key | 默认 | 含义 |
|---|---|---|
| `lid_behavior` | 1(helper 第一次开机强制写入一次;Pixel 默认 0) | 合盖:0 不处理,1 灭屏,2 锁屏 |
| `tb321fu_cover_enabled` | 1 | 0 = 忽略霍尔,始终当作开盖 |
| `tb321fu_edge_rotation` | 1 | 0 = 不同步旋转给触摸屏 |

## 验证

```bash
adb logcat -s Tb321fuHwPolicy
#   hall sensor bu52053nvx Hall Effect Sensor Wakeup registered=true
#   hall value 1.0 -> lid open
#   setEdgeInhibition(0) -> true      横屏后 setEdgeInhibition(1) 或 (3)
adb shell 'ush -c "cat /proc/panel_direction"'   # 横屏时 Right Up Direction!(90 degree)
adb shell dumpsys window | grep -i lid           # mLidState=LID_OPEN、getLidBehavior=LID_BEHAVIOR_SLEEP
adb shell settings get global tb321fu_lid_behavior_init   # 1
```

没有皮套可以用磁铁沿边框找霍尔位置:贴近时 log 出现 `lid closed` 并灭屏,拿开出现 `lid open` 并亮屏(`dumpsys power` 的 `mLastWakeReason=9`,即 LID)。

合盖后打不开屏:`settings put global tb321fu_cover_enabled 0`。要彻底回退,去掉本模块重新构建。
