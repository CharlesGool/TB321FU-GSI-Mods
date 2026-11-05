# slim/gsi-traces/mystic-vendor-overlays

## 做什么

删 `/system/mystic`(276K),里面 `vo/` 下 9 个 `*__tangorpro__auto_generated_rro_vendor.apk`(SettingsGoogle、SystemUITitan、framework-res、TeleService、StorageManagerGoogle、Traceur、Flipendo、DeviceDiagnostics 的 tangorpro vendor overlay)。

## 原理

这是 Mystic 把 Pixel Tablet 的 vendor overlay 收在 `/system/mystic/vo` 里,原本打算在它自己的安装流程里放到 `/vendor/overlay`。**镜像里没有任何脚本或 rc 引用这个目录**(grep `/system/bin`、`/system/etc/init` 都找不到),所以是死文件,从来没生效过。其中 framework-res 那个还带着 Pixel Tablet 屏幕的白平衡、色彩模式、圆角这类参数,留着是隐患,删掉。

(`slim/pixel-hardware` 的 dock-hub 清单 以前就顺手删过这个目录里的 `DockSetup…vendor.apk`,也印证了它不被引用。)

## 改动清单

- 删 `mystic/`。

## 输入 / 依赖

无。

## 换底包注意

别的 GSI 没有这个目录就跳过。

## 验证

`adb shell ls /system/mystic` 不存在。
