# 清单 · ambient-music

## 做什么

删 `product/etc/ambient`(52M),Pixel"正在播放"(Now Playing)用的歌曲指纹库,按语言分目录(de-de、es-es、fr-fr…)。

## 原理

Now Playing 靠手机常开的低功耗麦克风,把环境音和这个本地歌曲库比对,识别在放什么歌。需要 Pixel 的硬件配合(SoC 上的常开音频通路)。TB321FU 没有,这个库不会被用到。

**这是按用途推断的**,没有在真机上验证过"删了不出问题"。Now Playing 本身依赖的 Android System Intelligence(`DevicePersonalizationPrebuilt…`)我们保留着,它缺这个库时的行为我没测。万一刷后 ASI 反复报错,恢复这个目录或关掉本模块。

## 改动清单

- 删 `product/etc/ambient`。

## 输入 / 依赖

无。

## 换底包注意

底包里没有就跳过。

## 验证

刷机后看 `adb logcat -b crash` 里没有和 `ambient` / `NowPlaying` 相关的崩溃。
