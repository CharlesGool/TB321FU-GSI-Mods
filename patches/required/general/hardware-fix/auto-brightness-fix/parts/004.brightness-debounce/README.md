# brightness/brightness-debounce

## 做什么

自动亮度对环境光变化的反应速度用联想原厂的:变亮等 2 秒,变暗等 3 秒。

## 原理

`config_autoBrightnessBrighteningLightDebounce = 2000`、`config_autoBrightnessDarkeningLightDebounce = 3000`(毫秒),取自 联想原厂 TB321FU 的 `KirbyRowFrameworksOverlay.apk`(stock `product/overlay/`,包 `com.zui.android.overlay.kirby`,优先级 2000)。环境光变化要持续这么久才开始调亮度,值越大越"稳",越小越"灵"。ZUI 的框架默认是 4000/8000,联想相机型 overlay 压到 2000/3000。

## 改动清单

- 加 `product/overlay/tb321fu-brightness-debounce.apk`(静态 RRO)。

## 输入 / 依赖

无。

## 验证

自动亮度下,从暗处走到亮处,屏幕 2 秒左右开始变亮;走回暗处约 3 秒后变暗。
