# slim/now-playing — 去除 Now Playing(修音频断续)

## 做什么

删这两样(路径相对 system/):

| 路径 | 是什么 |
|---|---|
| `product/app/NowPlayingPrebuilt` | Now Playing 应用(环境音乐识别,包名 `com.google.android.apps.pixel.nowplaying`) |
| `product/etc/sysconfig/nowplaying_app_26q1.xml` | 它的 sysconfig(预装/权限声明) |
| `product/etc/firmware/music_detector.*` | 4 个声学模型(`.descriptor` / `.sound_model` / `.sound_model_2` / `.sound_model_tflite`),ASI 靠它起音乐识别(V1.1 加) |

## 为什么要删模型(V1.1)

V1.0 只删了 App,但真机上「文曲知音」还会自启动 —— **Android System Intelligence(ASI)** 本身也会从
`product/etc/firmware/music_detector.*` 这 4 个声学模型起环境音乐识别,仍常驻占录音。把模型删掉,ASI
就加载不了识别器,从根上关掉;且只删模型、**不动 ASI 本体**,实时字幕等不受影响。

## 为什么

Pixel 的 Now Playing 会常驻后台、持续占用录音(音频输入)会话做环境音乐识别。在 TB321FU 的
GSI 上(ZUI vendor 音频),这个常驻录音和正常播放抢音频通路,导致**声音断断续续**。
2026-11-07 在 DP11 真机上定位到就是它:删掉后音频恢复正常。

它是**独立应用**,不在 Android System Intelligence(ASI,`com.google.android.as`)里,所以删它
**不影响**实时字幕、智能识别文字等 ASI 功能。

## 输入

无。路径是 DP11.261016.003 底包的实际目录;换底包(新 DP11 / Canary 工厂包)时要重新核对
`product/app/` 下的 `NowPlayingPrebuilt` 目录名和 `nowplaying_app_*.xml` 文件名。

## 验证

删不到只记日志、不算失败(`remove_list`)。真机确认:设置里不再有 Now Playing,音频不再断续。
DP11 真机已确认删除后音频恢复正常(2026-11-07)。
