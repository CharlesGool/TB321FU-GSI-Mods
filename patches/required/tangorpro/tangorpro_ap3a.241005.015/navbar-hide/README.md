# navbar — 隐藏导航栏

> **ap3a 旧方案(特例)。** 2026-11-05 起通用版 `optional/navbar-hide`(V1.1)换成新方案:启动器收起高度 **1dp**、
> 底部是 Taskbar 时**不强切导航模式**(官方 BP1A 启动器上 0dp 会让"上滑多任务中途掉头"卡死)。本补丁保留 ap3a 上稳定的
> **旧方案**:收起高度 0dp(占位真正为 0)、原控制逻辑,V1.0 不变。只在 ap3a 底包上跑(底包 ID 门控);其它底包用通用版。

> 一个补丁(`navbar-hide`),内部 4 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`navbar-hide`),内部 4 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

像国产系统那样把底部导航栏藏了:不画提示线/小白条、App 用满全屏、不给底部让出高度,**手势照旧**(上滑回桌面/多任务、侧滑返回都在)。用 `heraldctl navbar hide|show|status` 切换。

| 部分 | 做什么 | 目标包 | 运行时开关 |
|---|---|---|---|
| [overlay-framework](parts/001.overlay-framework/) | 框架导航栏高度 = 0(手机模式给 App 的占位高度) | android | 由 control 开关 |
| [overlay-systemui](parts/002.overlay-systemui/) | SystemUI 手势提示线颜色全透明(手机模式) | com.android.systemui | 由 control 开关 |
| [overlay-launcher](parts/003.overlay-launcher/) | 启动器任务栏收起高度 = 0 + 小白条透明(平板模式) | com.google.android.apps.nexuslauncher | 由 control 开关 |
| [control](parts/004.control/) | `navbar hide\|show\|status` 命令 + 导航模式守护 | — | 就是开关本身 |

## 底部有两种,DPI 决定

- **低 DPI(平板模式,sw≥600dp)**:底部是启动器(NexusLauncher)的任务栏,App 看到的占位高度来自任务栏收起高度。→ `overlay-launcher`
- **高 DPI(手机模式)**:底部是 SystemUI 的导航栏,占位高度来自框架 `navigation_bar_height`,手势提示线是 SystemUI 画的。→ `overlay-framework` + `overlay-systemui`

要藏哪种,就装哪几个 overlay;两种都要能藏就三个都装。

## 独立性

三个 overlay 模块互相独立,各自单独启用都可以(没启用的那个对应的模式就不隐藏)。overlay 是**非静态** RRO,装上默认是关的,不开 `control` 它们什么也不做。`control` 依赖 [herald-core](../../required/general/herald-core/)(控制后端),它开关的是三个 overlay 包名;只装了其中几个时,`navbar hide` 对没装的包会报 `fail`,但装了的照样生效(三个全失败才算整体失败,不保存意愿)。

## 为什么非静态 + 每个 APK 单独一个目录

- 非静态才能用 `cmd overlay enable/disable` 运行时开关;状态存在 OMS 里,重启保留。
- **同一目录放多个包名不同的 APK,会被 PackageManager 当成一个包的拆分包,整目录作废**(V65 真机:三个放一个目录,`cmd overlay` 报 "Unable to retrieve overlay information",全没注册)。所以每个 APK 一个目录:`/system/product/overlay/<名字>/<名字>.apk`。
- 这三个目标(framework-res / SystemUITitan / NexusLauncher)的 resources.arsc 里没有 overlayable 声明,预装的 /product overlay 能覆盖它们的任意资源,签名不受限。

## 手势为什么不受影响

手势判定区是框架 `navigation_bar_gesture_height`(32dp),启动器 `TaskbarInsetsController` 的 `mandatorySystemGestures` 也用这个值,三个 overlay 都没碰它。`navigation_bar_frame_height`(48dp)也没动。

## 整组独立发布

可以带 `patches/required/tangorpro/tangorpro_ap3a.241005.015/navbar-hide/` + `toolkit/`。控制部分依赖 herald 控制后端的插件机制;如果不用 herald,三个 overlay 本身是标准 RRO,自己用 `cmd overlay enable --user 0 com.omk.navhide.android` 等命令也能开关(记得 `set-priority highest` 并重启启动器/SystemUI)。
