# navbar-hide/overlay-systemui

## 做什么

手机模式下把 SystemUI 画的手势提示线(底部那条小白条)变成全透明。

## 原理

`navigation_bar_home_handle_light_color` / `navigation_bar_home_handle_dark_color` 是手势提示线(home handle)在亮/暗背景下的颜色,设成 `#00000000` 就看不见了。线虽然看不见,下面的手势区还在。切换后要重启 SystemUI 才重新读取颜色(control 会处理)。

## 改动清单

- 加 `product/overlay/OmkNavHideSysUI/OmkNavHideSysUI.apk`(目录单独一个,0755 root:root `system_file`;APK 0644)。包名 `com.omk.navhide.systemui`,目标 `com.android.systemui`,非静态(默认关),优先级 999。

## 输入 / 依赖

无。开关由 [navbar-hide/control](../004.control/) 控制;不装 control 它默认关着什么都不做。预编译 APK 在 `files/`,源码在 `src/`,重编用 `build.sh`(需要 java、apktool 2.12.1+、zipalign、apksigner;或构建时设 `REBUILD_RRO=1`)。

## 换底包注意

资源名依赖 SystemUITitan 的实现;换了 SystemUI(不是 Titan)要重新核对。

## 踩过的坑

- V65:三个 overlay 放在同一目录 `product/overlay/OmkNavHide/`,系统把它当一个包的拆分包,包名不一致整目录作废,全没注册。V66 拆成每个 APK 一个目录。

## 验证

```bash
adb shell "cmd overlay list --user 0 | grep navhide"   # 能看到 com.omk.navhide.systemui,状态 [ ](不是 missing)
adb shell heraldctl navbar hide                            # 对应的 overlay 变成 [x]
```
