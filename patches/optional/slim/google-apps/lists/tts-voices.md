# 清单 · tts-voices

## 做什么

删 `product/tts/google`(78M),Google 文字转语音的语音数据。

## 原理

这是 GoogleTTS 应用(`product/app/GoogleTTS`)预装的语音包。应用已经被 [google-apps 清单](google-apps.md) 删掉,数据没人读了。以后从 Play 装回 Google TTS 时它会自己下载语音数据。

## 改动清单

- 删 `product/tts/google`。

## 输入 / 依赖

无。**功能上**要求 GoogleTTS 应用已被删(google-apps 清单);留着 GoogleTTS 的话把本模块也关掉,否则它没有预装语音。构建上互不依赖。

## 换底包注意

底包里没有这个目录就只 log 一句跳过。

## 验证

`adb shell ls /product/tts` 无 google 目录。装回 Google TTS 后能正常下载语音。
