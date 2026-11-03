# free-rotation — 自由旋转

## 做什么

允许四个方向都能自动旋转,包括**竖屏倒过来(180°)**。

## 原理

AOSP 的 `config_allowAllRotations` 决定自动旋转时能不能转到"倒过来"的方向。默认只在大屏(最小宽度够大)上放行;"显示大小"调大后(例如 density 444,最小宽度约 576dp,不到 600dp),系统就把本机当手机,不再允许竖屏倒过来。overlay(目标包 `android`)直接设成 true,和显示大小无关。

旧测试记录里的"转 180° 跟着翻"指的是横屏时 90° 和 270° 互相翻,和这里的竖屏倒过来不是一回事;竖屏倒过来我们此前没有明确打开过。**这个推测没有真机验证。**

## 和 rotation-fix 的关系

[`rotation-fix`](../../required/tangorpro/rotation-fix/)(必选)修的是"只能横屏的应用画面倒过来"和底座方向,是 bug 修复,不能关。本补丁只管"允许哪几个方向",可以不要,不影响 rotation-fix。

## 改动清单

- 加 `product/overlay/tb321fu-free-rotation.apk`(0644 root:root `system_file`,静态 RRO,优先级 322)。带 `requiredSystemPropertyName=ro.product.vendor.device`、`requiredSystemPropertyValue=TB321FU`,只在这台机器的 vendor 上生效。

## 输入 / 依赖

无。预编译 APK 在 `files/`,源码 `src/`;改了 `src/` 后用 `REBUILD_RRO=1` 重编。

## 换底包注意

资源名是 AOSP 框架的。

## 验证

把平板竖着拿,头朝下转 180°,开自动旋转,画面应该跟着翻过来。
