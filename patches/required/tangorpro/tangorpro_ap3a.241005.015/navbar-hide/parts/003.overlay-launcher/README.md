# navbar-hide/overlay-launcher

## 做什么

平板模式(低 DPI)下,让启动器的任务栏收起后不占高度,小白条也看不见。

## 原理

平板模式的底部是 NexusLauncher 的任务栏。收起(stashed)状态下,`TaskbarStashController.getContentHeightToReportToApps()` 返回 `mStashedHeight`,它来自 `DeviceProfile.stashedTaskbarHeight`,也就是 `transient_taskbar_stashed_height`(32dp)和 `taskbar_stashed_size`(24dp)两个 dimen。把它们设成 0dp,App 看到的底部占位就是 0;收起时的小白条颜色 `taskbar_stashed_handle_{light,dark}_color` 设成透明。手势区用的是框架 `navigation_bar_gesture_height`,没动。切换后要重启启动器才重新读取(control 会处理)。

## 改动清单

- 加 `product/overlay/OmkNavHideLauncher/OmkNavHideLauncher.apk`(目录单独一个,0755 root:root `system_file`;APK 0644)。包名 `com.omk.navhide.launcher`,目标 `com.google.android.apps.nexuslauncher`,非静态(默认关),优先级 999。

## 输入 / 依赖

无。开关由 [navbar-hide/control](../004.control/) 控制;不装 control 它默认关着什么都不做。预编译 APK 在 `files/`,源码在 `src/`,重编用 `build.sh`(需要 java、apktool 2.12.1+、zipalign、apksigner;或构建时设 `REBUILD_RRO=1`)。

## 换底包注意

资源名来自 NexusLauncherRelease(Android 15 的 Pixel 启动器)。换成别的启动器、或 Pixel 启动器大版本改了任务栏实现,要重新反编译核对这几个 dimen。

## 踩过的坑

- V65:三个 overlay 放在同一目录 `product/overlay/OmkNavHide/`,系统把它当一个包的拆分包,包名不一致整目录作废,全没注册。V66 拆成每个 APK 一个目录。

## 验证

```bash
adb shell "cmd overlay list --user 0 | grep navhide"   # 能看到 com.omk.navhide.launcher,状态 [ ](不是 missing)
adb shell heraldctl navbar hide                            # 对应的 overlay 变成 [x]
```
