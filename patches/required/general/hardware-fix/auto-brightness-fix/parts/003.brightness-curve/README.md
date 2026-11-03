# brightness/brightness-curve

## 做什么

自动亮度用联想 TB321FU 原厂的曲线:环境光(lux)→ 屏幕亮度(尼特)。

## 原理

GSI 的 framework 里这四个数组是空的。overlay(目标包 `android`)补上 联想原厂 TB321FU 的 `KirbyRowFrameworksOverlay.apk`(stock `product/overlay/`,包 `com.zui.android.overlay.kirby`,优先级 2000) 里的值:

| lux 档位 `config_autoBrightnessLevels`(原厂 14 档 + V72 加 2 档) | 5, 15, 40, 100, 180, 400, 550, 1000, 1500, 2000, 2500, 3000, 4000, 5000, **8000, 10000** |
|---|---|
| 对应尼特 `config_autoBrightnessDisplayValuesNits`(比 lux 多一个,第一个是 0 lux 的值) | 8, 8, 30, 70, 100, 120, 150, 180, 210, 270, 340, 420, 480, 550, 650, **741, 782** |
| `config_screenBrightnessNits` | 0, 8, 30, 70, 100, 120, 150, 180, 210, 270, 340, 420, 480, 550, 650 |
| `config_screenBrightnessBacklight`(0–255) | 0, 6, 15, 36, 51, 61, 76, 92, 107, 138, 173, 214, 245, 255, 255 |

暗处(≤5 lux)8 尼特,室内 100–400 lux 是 100–150 尼特,到 5000 lux 才 650 尼特。

**V72 在原厂曲线末尾多加了两档(不是原厂的)**:8000 lux → 741 尼特(面板 HBM 起点),10000 lux 以上 → 782 尼特(面板峰值)。原厂自动亮度最高只到 650 尼特,从来不会进 HBM;配合 [hbm-unlimited](../../../../../../optional/brightness/hbm-unlimited/),户外强光下自动亮度也能顶到面板真正的最高亮度。不想要就把这两档从 `src/res/values/arrays.xml` 删掉重编。

面板自己的"滑块 → 尼特"关系在 `vendor/etc/displayconfig/display_id_*.xml`(0.23 尼特到 782 尼特),Android 15 的 `DisplayDeviceConfig` 有这份文件就用它,后两个数组基本不起作用,留着只是和原厂一致。

**旧版本的错误**:V66/V67/V69/V70 装的曲线(lux 10/60/210/350/420/1000/1001 → 40/40/100/150/300/420/490/500 尼特)**不是 TB321FU 原厂的**(像是二代 TB320FC 的),暗处下限 40 尼特,400 lux 就 386 尼特,所以偏亮、低亮度下不去。V71 起换成上面的原厂值。

## 为什么还带着一个 bool(V69 的教训)

只含数组的 overlay 在真机上 `STATE_NO_IDMAP`(idmap 没生成),静态 overlay 没 idmap 会让 zygote 每次 fork 应用都 `JNI FatalError`,所有应用进程崩溃,卡开机动画。所以这个包必须至少带一个标量资源:`config_automatic_brightness_available=true`(曲线本来就要自动亮度可用才有意义),和 `brightness/auto-brightness` 同值,重复无害。

## 改动清单

- 加 `product/overlay/tb321fu-auto-brightness-curve.apk`(0644 root:root `system_file`,静态 RRO,优先级 321),包名 `…tb321fu.autobrightnesscurve`。
- **V71 起换了文件名和包名**(原来是 `tb321fu-brightness-curve.apk` / `…brightnesscurve`):保数据升级时 `/data/resource-cache` 里留着同名的损坏 idmap,会让 idmap2d 崩溃、这个 overlay 永远 NO_IDMAP。新名字绕开旧文件;[overlay-idmap-reset](../../../../../../optional/overlay-idmap-reset/) 开机时再把旧文件清掉。

## 输入 / 依赖

无。数值写死在 `src/res/values/arrays.xml`,来源见上。

## 换底包注意

资源名是 AOSP 框架的。换原厂固件(面板或亮度参数变了)要从新固件的 `KirbyRowFrameworksOverlay` 重新取数组。

## 验证

`adb shell cmd overlay list --user 0 | findstr brightnesscurve` 必须是 `[x]`,不能是 `---`(NO_IDMAP)。曲线是否生效:`adb shell "dumpsys display | grep -i -E 'autoBrightness|nits'"`。体感:暗室开自动亮度应该很暗(约 8 尼特)。
