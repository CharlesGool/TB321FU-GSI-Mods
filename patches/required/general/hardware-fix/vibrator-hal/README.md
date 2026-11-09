# TB321FU：振动 HAL（两颗马达 + primitives + 同步振动）

## 现状（test-v2.0 实测）

`dumpsys vibrator_manager`：
- `Legacy HAL VibratorManager`，`vibratorIds = [0]`；
- `capabilities = [ON_CALLBACK, PERFORM_CALLBACK, AMPLITUDE_CONTROL, EXTERNAL_CONTROL]`；
- `supportedPrimitives = []`。

带来的问题：
- Pixel 的 primitives 触感（键盘、滑块、滚动等 `VibrationEffect.Composition`）一个都用不了，只能退化成预设或开关式振动；
- 两颗马达框架只认 1 个。

## 原因（2026-11-09 反汇编核实）

| 环节 | 事实 |
|---|---|
| 硬件 | 两颗 Awinic AW86937(i2c-3 `0x5b` = i2c client `haptic_hv_l`/vibrator_l,`0x5a` = `haptic_hv_r`/vibrator_r;总线号随探测顺序,代码按 client 名找),驱动 `haptic_hv` |
| 驱动对上层的接口 | 除了 LED sysfs，还给每颗马达注册了一个 **input force-feedback 设备**，名字都叫 `aw-haptic-hv`（event3 / event4）。支持 FF_RUMBLE / PERIODIC / CONSTANT / **CUSTOM** / GAIN |
| vendor HAL | `vendor.qti.hardware.vibrator.impl.so` 只在设备名是 `qcom-hv-haptics` / `qti-haptics` 时才走 input FF（primitives 就在这条路上）。名字对不上，log 里报 "not a qcom/qti haptics device"，于是退到 LED 模式 |
| RichTap | vendor 里有 `libaacvibrator.so`，但没有任何进程加载它，也没有注册 RichTap 服务 |

驱动 input FF 的语义（从 `haptic.ko` 的 `input_upload_effect` / `input_playback` / `input_set_gain` 反汇编得到）：

| 上传的 effect | 效果 |
|---|---|
| `FF_CONSTANT`，`replay.length = N` | 连续振 N ms |
| `FF_PERIODIC` + `FF_CUSTOM`，`custom_data[0] = 1..3` | 一次性播放 RAM 波形 1..3，带刹车（干脆的点击） |
| `FF_CUSTOM` id = 4 / 5 | 内置 45 ms / 13 ms 短振 |
| `FF_CUSTOM` id ≥ 6 | 播放 RTP 文件 |
| `EV_FF code=id value=1/0` | 播放 / 停止。**驱动只认最后一次上传的 effect，忽略 id**，所以每次播放前都要先上传 |
| `EV_FF code=FF_GAIN value=0..0x7fff` | 增益寄存器 0..0x80（100 %） |

RAM 波形（24 kHz，来自 `haptic_ram.bin`）：

| 波形 | 时长 | 特征 |
|---|---|---|
| 1 | 16 ms | f0 上 3 个周期，满幅（重击） |
| 2 | 11.4 ms | 2 个周期（标准点击） |
| 3 | 10.3 ms | 约 290 Hz（短促的 tick） |

## 做法

新增一个系统侧原生服务 `tb321fu-vibrator`，实现 `android.hardware.vibrator.IVibratorManager/default`（AIDL V2）。

A17 的 `VintfHalVibratorManager.createHalVibratorManager()` 先看 `IVibratorManager/default` 有没有声明，有就用它，不再碰 vendor 的 `IVibrator/default`。所以：
- **不用改 services.jar，也不用改 vendor**；
- vendor 的 IVibrator 还在，只是框架不再用它。

服务提供的能力：

| 项目 | 内容 |
|---|---|
| vibratorIds | `[0, 1]`：0 = 左（0x5b），1 = 右（0x5a） |
| IVibrator capabilities | ON_CALLBACK、PERFORM_CALLBACK、AMPLITUDE_CONTROL、COMPOSE_EFFECTS、GET_RESONANT_FREQUENCY |
| IVibratorManager capabilities | SYNC、PREPARE_ON/PERFORM/COMPOSE、MIXED_TRIGGER_*、TRIGGER_CALLBACK |
| on(ms) | FF_CONSTANT；amplitude → FF_GAIN |
| perform（预设效果） | CLICK→波形 2、DOUBLE_CLICK→波形 2 ×2（间隔 85 ms）、TICK→波形 3、TEXTURE_TICK→波形 3 半幅、THUD→波形 1、POP→波形 3、HEAVY_CLICK→波形 1；强度 LIGHT / MEDIUM / STRONG = 0.55 / 0.8 / 1.0 |
| primitives | CLICK→2、THUD→1、LIGHT_TICK→3（0.6 倍）、LOW_TICK→1（0.45 倍），scale → 增益 |
| primitives（可关） | SPIN / QUICK_RISE / SLOW_RISE / QUICK_FALL：FF_CONSTANT 加每 5 ms 调一次增益的包络 |

`Vibrator.vibrate()` 默认会让两颗马达同时振（框架的并行 CombinedVibration，用 prepareSynced/triggerSynced 同时起振）。

技术说明：
- binder 协议是照 framework.jar 里的 Java stub 手写的：事务号、parcel 布局、CompositeEffect 的 size 头都已对过。
- 只要 NDK 就能编：
  - 公开的 libbinder_ndk API 直接链接；
  - `AServiceManager_addService` 和 `ABinderProcess_*` 在运行时用 dlsym 取。
- 不会去读 `vibrator_*/f0` 或 `cali` 节点：这两个节点一读，驱动就会真的驱动马达去测 f0。共振频率直接用 DT 的 `f0_pre`（170.0 Hz）。

SELinux：
- 跑在 herald 域（permissive），和 herald 其他 payload 一样，不需要新类型；
- system_server → herald 的 binder call/transfer 在 herald-core 里已经放行（V62）；
- `IVibratorManager/default` 在平台的 service_contexts 里本来就是 `hal_vibrator_service`。

## 构建和安装(本模块)

- `files/tb321fu-vibrator` 是预编译件:`NDK=/opt/android/sdk/ndk/29.0.14206865 src/build.sh`(NDK r29、API 34,`-static-libstdc++`),
  NEEDED 只有 libbinder_ndk / liblog / libdl / libm / libc。已对照 DP11 底包的 libbinder_ndk.so / liblog.so 核对过全部导入符号,
  dlsym 用的 `AServiceManager_addService`、`ABinderProcess_*` 都在。构建时 `REBUILD_VIBRATOR=1 NDK=...` 现编。
- apply.sh 一次装三件(缺一不可):

```
files/tb321fu-vibrator      -> /system/etc/herald_payload/bin/tb321fu-vibrator   0755 u:object_r:herald_exec:s0
files/tb321fu-vibrator.rc   -> /system/etc/init/tb321fu-vibrator.rc              0644 u:object_r:system_file:s0
files/tb321fu-vibrator.xml  -> /system/etc/vintf/manifest/tb321fu-vibrator.xml   0644 u:object_r:system_file:s0
```

**⚠ 千万不能只装 VINTF 声明而不装服务**:system_server 会一直等 `IVibratorManager/default` 注册,开机卡在开机动画。
init 以 `seclabel u:r:herald:s0` 直接起二进制:herald-core 已放行 init → herald 的 transition 和 herald_exec 的 entrypoint。

服务的容错：
- 即使一颗马达都没找到，服务也会注册（返回 0 个 vibrator），不会让 system_server 卡住；
- 崩溃后 init 会自动重启它。

## 刷入后验证

```bash
adb logcat -d -s tb321fu-vibrator
#   2 motor(s), f0 170.0 Hz
#   registered android.hardware.vibrator.IVibratorManager/default
adb shell dumpsys vibrator_manager | grep -E 'VibratorManager|vibratorIds|capabilities|supportedPrimitives|supportedEffects'
#   应为 VintfHalVibratorManager / Default HAL VibratorManager，vibratorIds = [0, 1]，有 COMPOSE_EFFECTS 和 primitives
adb shell dumpsys android.hardware.vibrator.IVibratorManager/default

# 单独测（-f 忽略设置里的强度/静音）
adb shell cmd vibrator_manager synced -f oneshot 300                       # 两颗一起振 300 ms
adb shell cmd vibrator_manager synced -f prebaked 0                        # CLICK
adb shell cmd vibrator_manager synced -f prebaked 5                        # HEAVY_CLICK
adb shell cmd vibrator_manager synced -f primitives 1 7 2                  # CLICK、LIGHT_TICK、THUD
adb shell cmd vibrator_manager synced -f primitives -s 0.3 1 -w 100 -s 1 1 # 轻点击，隔 100 ms 再一个满幅点击
adb shell cmd vibrator_manager synced -f primitives 4 6                    # QUICK_RISE、QUICK_FALL
adb shell cmd vibrator_manager combined -f -v 0 primitives 1               # 只有左马达
adb shell cmd vibrator_manager combined -f -v 1 primitives 1               # 只有右马达
adb shell cmd vibrator_manager list                                        # 应为 [0, 1]
```

然后在系统里试：键盘打字、拖动亮度和音量滑块、设置 → 声音和振动 → 振动和触感（这里能看到强度滑块）。

## 可调属性（`adb shell setprop … ; adb shell stop tb321fu_vibrator; adb shell start tb321fu_vibrator`）

| 属性 | 默认 | 含义 |
|---|---|---|
| `persist.tb321fu.vibrator.gain_max` | 100 | 所有效果的增益上限（10..100，单位 %） |
| `persist.tb321fu.vibrator.ramps` | 1 | 0 = 不报 SPIN / QUICK_RISE / SLOW_RISE / QUICK_FALL（如果包络手感不好） |
| `persist.tb321fu.vibrator.motors` | 3 | 3 = 两颗；1 = 只用左；2 = 只用右 |
| `persist.tb321fu.vibrator.f0_dhz` | 1700 | 上报的共振频率，单位 0.1 Hz |

改 `motors` 或 `ramps` 后要重启 system_server（或整机重启），因为框架在开机时缓存了 VibratorInfo。

## 尚未验证

- 编译已通过(NDK r29,零警告),还没上机。
- 真机手感。RAM 波形和 primitive 的对应关系是按波形参数选的，需要你实际摸一遍再调。

## 回退

删掉上面三个文件，系统就回到 vendor 的 IVibrator/default。
