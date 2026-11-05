# navbar — 隐藏导航栏 · BP1A 适配版

> **2026-11-05 决定:新方法不并回通用版。** 通用版 `optional/navbar-hide`(V1.0,0dp)在 ap3a(Mystic 启动器)上是更完美的方案,
> 保持不动,ap3a 继续用它。本专属版的 1dp 是为保住官方 BP1A 启动器的手势收尾付出的折中(用户细看后认为"还有一点不完美",
> 具体点待确认),**只在 BP1A 用**。cp3a 若要同样处理,另开它自己的版本门控补丁。

> **BP1A 专属版本**(底包 ID 门控:`required/tangorpro/tangorpro_bp1a.250505.005/`,V1.1)。通用版 `optional/navbar-hide`(V1.0)在 ap3a 上
> 稳定,但在官方 BP1A 底包上"上滑到多任务**中途**掉头"会卡死:App 点不动、侧滑返回失效(多任务完整结束、或点一下应用就恢复)。
> 2026-11-05 真机 + `dumpsys` 定位,与通用版的两处差异:
>
> 1. **启动器 overlay 的收起高度 0dp → 1dp**(`003.overlay-launcher`)。BP1A 官方启动器里 `transient_taskbar_stashed_height` /
>    `taskbar_stashed_size` 不只决定占位,还决定手势收尾的判定区,清成 0 手势就收不了尾。1dp(444 密度约 3px)肉眼不可见,
>    占位等于去掉,手势正常。依据:真机 `adb install -r` 逐个换值,1dp 即不卡。
> 2. **底部是 Taskbar 时不再强切导航模式**(`004.control` 的 `herald_nav_set`)。官方 BP1A 启动器在手机尺寸的显示大小(sw<600dp)
>    下底部仍是启动器的 `Taskbar` 窗口(`mNavigationBar=Taskbar`,没有 `NavigationBar0`),原逻辑按"sw<600 就是 SystemUI 导航栏"
>    去把导航模式 手势→三键→手势 强切一遍,对 Taskbar 是白折腾(hide 那一秒连跑十次转场)。现在 `bar=taskbar` 只杀启动器。
>
> 框架高度 overlay(`navigation_bar_height=0`)和 SystemUI 提示线 overlay 保持不变;此底包上底部栏是 Taskbar 时它们不起作用,
> 隐藏靠启动器 overlay。overlay APK 版本号 200(高于测试时手动装的 101–105,刷入后系统自带版本不会被旧的数据分区更新压住)。

# navbar — 隐藏导航栏

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

可以带 `patches/required/tangorpro/tangorpro_bp1a.250505.005/navbar-hide/` + `toolkit/`。控制部分依赖 herald 控制后端的插件机制;如果不用 herald,三个 overlay 本身是标准 RRO,自己用 `cmd overlay enable --user 0 com.omk.navhide.android` 等命令也能开关(记得 `set-priority highest` 并重启启动器/SystemUI)。
