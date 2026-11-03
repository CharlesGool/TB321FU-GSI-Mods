# brightness/auto-brightness

## 做什么

让设置里有"自适应亮度"开关。

## 原理

Pixel 框架默认 `config_automatic_brightness_available=false`,所以没有自适应亮度。overlay(目标包 `android`)设 `config_automatic_brightness_available = true`(`bools.xml`)。

只开开关,没有亮度曲线时自动亮度会用框架默认曲线;要用原厂的曲线同时启用 [brightness-curve](../003.brightness-curve/)。两个模块互相独立。

## 改动清单

- 加 `product/overlay/tb321fu-auto-brightness.apk`(0644 root:root `system_file`,静态 RRO)。带 `requiredSystemPropertyName=ro.product.vendor.device`、`requiredSystemPropertyValue=TB321FU`,只在这台机器的 vendor 上生效。

## 输入 / 依赖

无。预编译 APK 在 `files/`,源码 `src/`,重编见组 README。

## 换底包注意

资源名是 AOSP 框架的,Android 15 这代稳定。

## 验证

设置 → 显示 里出现"自适应亮度"。
