# brightness/min-brightness

## 做什么

手动亮度的最低档用联想原厂的值,更暗。

## 原理

overlay(目标包 `android`)设两个资源,取自 联想原厂 TB321FU 的 `KirbyRowFrameworksOverlay.apk`(stock `product/overlay/`,包 `com.zui.android.overlay.kirby`,优先级 2000):

- `config_screenBrightnessSettingMinimum = 1`(旧的 0–255 刻度)
- `config_screenBrightnessSettingMinimumFloat = 0.0029311`(Android 15 用的浮点刻度,≥0 时优先于上一项)

按面板的"亮度 → 尼特"表(`vendor/etc/displayconfig`),0.0029311 约 **0.86 尼特**;旧版本装的是 2/255 ≈ 1.9 尼特。

## 改动清单

- 加 `product/overlay/tb321fu-min-brightness.apk`(静态 RRO)。

## 输入 / 依赖

无。

## 换底包注意

数值是这块屏幕的,别的设备不能直接用。

## 验证

把亮度条拉到最左,夜里应该很暗但不黑屏(0.86 尼特)。
