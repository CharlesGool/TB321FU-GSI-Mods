# rotation-reverse-fix

## 做什么

修"只能横屏的应用(B 站全屏等)画面倒过来"。

## 原理

Pixel Tablet(tangorpro)的自然方向是**横屏**,它的 framework overlay 设了 `config_reverseDefaultRotation=true`,把默认旋转反过来。TB321FU 的自然方向是**竖屏**,这个值为 true 就让"横屏"和"反向横屏"对调,强制横屏的应用就倒了。overlay(目标包 `android`)把它改回 false(`bools.xml`)。

## 改动清单

- 加 `product/overlay/tb321fu-rotation-reverse-fix.apk`(0644 root:root `system_file`,静态 RRO)。带 `requiredSystemPropertyName=ro.product.vendor.device`、`requiredSystemPropertyValue=TB321FU`,只在这台机器的 vendor 上生效。

## 输入 / 依赖

无。预编译 APK 在 `files/`,源码 `src/`,重编见组 README。

## 换底包注意

别的 GSI 如果本来就没设反向,覆盖成默认值无害。

## 验证

B 站全屏方向正确,把平板转 180° 画面跟着翻。V5 验证过:`LANDSCAPE → ROTATION_90`。
