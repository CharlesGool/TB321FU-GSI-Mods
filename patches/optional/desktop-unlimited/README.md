# desktop-unlimited — 桌面模式不限应用数

Android 17 的桌面模式(桌面窗口)默认最多同时开 4 个应用,再开会把最早的最小化。

## 原理(DP11 SystemUITitan 里核实)

`WMShellBaseModule.provideDesktopConfig`:
`maxTaskLimit = SystemProperties.getInt("persist.wm.debug.desktop_max_task_limit", res.getInteger(config_maxDesktopWindowingActiveTasks))`。
`WMShellModule.provideDesktopTasksLimiter` 里 `maxTaskLimit <= 0` 就不创建 `DesktopTasksLimiter`,也就没有上限。

本补丁只在 system `build.prop` 写 `persist.wm.debug.desktop_max_task_limit=0`(`DESKTOP_MAX_TASKS=N` 可改成固定值)。
不改 APK、不改 framework。

## 运行时改

persist 属性,`setprop persist.wm.debug.desktop_max_task_limit 8` 后重启 SystemUI(或整机重启)生效,/data 里的值优先于 build.prop。
