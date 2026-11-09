# TB321FU：耗电统计（power profile / power stats）

## 结论先说

体检报告里写的“没有 power stats HAL，电池用量里看不到按硬件拆分的耗电”**说重了**：
- 电池用量本来就是按硬件拆分的。`dumpsys batterystats` 里有 screen、cpu、wifi、bluetooth、sensors 各自的 mAh。
- 计算用的是 **vendor overlay 里本机专用的 power_profile**，和原厂一样：
  - 来源：`/vendor/overlay/FrameworksResTarget_Vendor.apk`，在 GSI 下已启用；
  - 电池容量 6550 mAh；
  - 四簇 CPU 的频点和本机 cpufreq 逐个对得上，包括大核的 4 个 boost 频点。

| 项目 | 情况 | 处理 |
|---|---|---|
| power.stats HAL | 原厂 vendor 也没有；硬件上也没有 ODPM 这类分路电量计。加一个也测不出东西，只会把估算值换个名字 | **不做** |
| audio / video 耗电 | vendor 的 power_profile 用的是老键名 `dsp.audio` / `dsp.video`，现在的 PowerProfile 读 `audio` / `video`，所以音频、视频播放的耗电一直按 0 算 | **RRO 补上**（本目录） |

## RRO

`src/`(构建产物 `files/tb321fu-power-profile.apk`,`REBUILD_RRO=1` 时现编):

| 项目 | 内容 |
|---|---|
| `res/xml/power_profile.xml` | 原样照抄 vendor 的版本（AXML 解码后逐值对过），只多两行：`audio = 48`、`video = 70`（数值取自 vendor 的 `dsp.audio` / `dsp.video`），老键名保留 |
| `AndroidManifest.xml` | target `android`,`isStatic`,priority 324(接 tb321fu 系列 overlay 的编号),只在 `ro.product.vendor.device=TB321FU` 时生效 |

/product 的 overlay 优先级高于 /vendor 的 overlay，所以会覆盖 vendor 的 power_profile。

apply.sh 把它放到 `/product/overlay/tb321fu-power-profile.apk`。

## 验证

```bash
adb shell cmd overlay list android | grep powerprofile         # [x] com.lenovo.tb321fu.overlay.powerprofile
# 放一段音乐或视频，息屏放几分钟，然后看 audio/video 有没有出现非 0 值
adb shell dumpsys batterystats | grep -A12 'Estimated power use' | grep -E 'audio|video'
```
