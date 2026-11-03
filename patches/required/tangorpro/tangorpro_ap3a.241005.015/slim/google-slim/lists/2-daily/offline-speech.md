# 清单 · offline-speech

## 做什么

删 `product/usr/srec`(92M),离线语音识别模型。

## 原理

目录里是完整的 en-US 离线语音识别模型(`acousticmodel`、`endtoendmodel`、`g2p`、`context_prebuilt`……)加 de/es/fr/it/ja 等语言包,是系统级的设备端语音识别模型。Live Caption(实时字幕)、离线语音输入可能用到,所以放在第 2 级(日常应用)而不是默认的第 1 级:选了 2 级,就表示不用这些功能。

## 改动清单

- 删 `product/usr/srec`。

## 输入 / 依赖

无。

## 换底包注意

底包里没有就跳过。

## 验证

`adb shell ls /product/usr` 无 srec。(选 1 级时 Live Caption 能打开、能出字幕;Gboard 离线语音输入能用。)
