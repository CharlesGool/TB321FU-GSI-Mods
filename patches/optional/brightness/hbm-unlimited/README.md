# brightness/hbm-unlimited

## 做什么

去掉 HBM"激发亮度"的时间限制:手动把亮度条拉满,可以一直保持面板真正的最高亮度(782 尼特)。

分工:不要求强光(`<minimumLux>`=0)由必选的自动亮度修复 `display-config` 部分负责;不打本补丁时 782 尼特有原厂时间限制(30 分钟窗口最多 5 分钟,剩余不足 1 分钟不再进),之后压回 741 尼特。

## 原理

面板自己的亮度配置在原厂 `vendor/etc/displayconfig/display_id_<屏幕ID>.xml`(高通):亮度 → 尼特表(0.23 到 782 尼特)和 `<highBrightnessMode>`:亮度超过 `transitionPoint`(0.85,约 741 尼特)的部分是 HBM,只在**环境光 ≥ 10000 lux** 才放行,**30 分钟窗口里最多 5 分钟**,不够 1 分钟配额不再进。所以室内手动拉满只有 741 尼特。

Android 15 的 `DisplayDeviceConfig` 找配置的顺序是**先 `/product/etc/displayconfig/`,再 `/vendor/etc/displayconfig/`**(在 V71 的 `services.jar` 里核对过)。本模块从原厂 vendor 取这份 xml,只放宽 HBM 的限制,放进 `/product/etc/displayconfig/`,盖过 vendor 的:

- `<minimumLux>` → 0(不要求强光;本来由 display-config 做,这里也保留)
- `<timeMaxSecs>` → 等于窗口长度(不限时)、`<timeMinSecs>` → 1
- 亮度→尼特表、`transitionPoint`、HDR 比例表、升降速都**原样不动**。

## 风险(请知情)

- 持续高亮会发热;面板和电池老化会更快。原厂的光线和时间限制就是为这个设的。系统自己的温控降亮度(thermal)不受影响,过热时还是会被压下去。
- 这是推测 + 源码核对:没有真机验证 GSI 会不会读到 product 目录里的这份。请用 `adb shell "dumpsys display | grep -i -E 'highBrightness|hbm|transition|nits'"` 确认。

## 改动清单

- 加 `product/etc/displayconfig/display_id_*.xml`(0644 root:root `system_file`)。

## 输入 / 依赖

`STOCK_VENDOR_IMG`(原厂 vendor 镜像)。不依赖其他模块。想恢复原厂行为,从 `MODS` 里删掉本模块即可。

## 换底包注意

换原厂固件(面板或配置变了)会自动用新固件里的 xml 重新生成;但脚本要求里面有 `<highBrightnessMode>`、`<minimumLux>`、`<timeWindowSecs>`、`<timeMaxSecs>`、`<timeMinSecs>`,缺了会报错停下。

## 验证

室内手动拉满,亮度应明显高于以前(741 → 782 尼特,肉眼差别不大;主要看 `dumpsys display`)。长时间拉满并留意机身温度。
