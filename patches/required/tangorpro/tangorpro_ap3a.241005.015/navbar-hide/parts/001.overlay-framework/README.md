# navbar-hide/overlay-framework

## 做什么

手机模式(高 DPI)下,让系统导航栏不占高度:App 底部不再给导航栏让位。

## 原理

框架的 `navigation_bar_height`、`navigation_bar_height_landscape`、`navigation_bar_width` 决定 SystemUI 导航栏给 App 报告的 inset。三个都设成 0dp,App 看到的导航栏区域就是 0。**不动** `navigation_bar_frame_height` 和 `navigation_bar_gesture_height`,所以手势判定区不变。

## 改动清单

- 加 `product/overlay/OmkNavHideFw/OmkNavHideFw.apk`(目录单独一个,0755 root:root `system_file`;APK 0644)。包名 `com.omk.navhide.android`,目标 `android`,非静态(默认关),优先级 999。

## 输入 / 依赖

无。开关由 [navbar-hide/control](../004.control/) 控制;不装 control 它默认关着什么都不做。预编译 APK 在 `files/`,源码在 `src/`,重编用 `build.sh`(需要 java、apktool 2.12.1+、zipalign、apksigner;或构建时设 `REBUILD_RRO=1`)。

## 换底包注意

这三个资源名在 Android 15 稳定;换 Android 版本要确认名字没变。

## 踩过的坑

- V65:三个 overlay 放在同一目录 `product/overlay/OmkNavHide/`,系统把它当一个包的拆分包,包名不一致整目录作废,全没注册。V66 拆成每个 APK 一个目录。

## 验证

```bash
adb shell "cmd overlay list --user 0 | grep navhide"   # 能看到 com.omk.navhide.android,状态 [ ](不是 missing)
adb shell heraldctl navbar hide                            # 对应的 overlay 变成 [x]
```
