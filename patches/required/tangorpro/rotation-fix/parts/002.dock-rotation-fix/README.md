# dock-rotation-fix

## 做什么

去掉 Pixel Tablet 底座的方向设置。

## 原理

`config_deskDockRotation` 在 tangorpro 上是 270(Pixel Tablet 底座的方向),TB321FU 没有底座,恢复 AOSP 默认 -1(`integers.xml`,目标包 `android`)。

## 改动清单

- 加 `product/overlay/tb321fu-dock-rotation-fix.apk`(0644 root:root `system_file`,静态 RRO)。带 `requiredSystemPropertyName=ro.product.vendor.device`、`requiredSystemPropertyValue=TB321FU`,只在这台机器的 vendor 上生效。

## 输入 / 依赖

无。预编译 APK 在 `files/`,源码 `src/`,重编见组 README。

## 换底包注意

只覆盖这一个资源。

## 验证

正常使用方向不受影响(没有底座可测)。
