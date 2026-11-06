# webview-full — 完整 WebView

## 问题

DP11(Android 17)user-v1.0 真机:谷歌账号登录等用到 WebView 的界面一打开就闪退,系统里没有可用的 WebView(2026-11-06)。

不是精简删掉的。Pixel 镜像的 WebView 本来就是"占位 + 压缩包":

- `product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk`(12KB 占位)
- `product/app/WebViewGoogle/WebViewGoogle.apk.gz`(真正的 WebView,压缩)

首次开机由 PackageManager 解压到 `/data/app` 再启用。构建产物里这两个文件和底包一样,但本机上没解压成功,WebView 不可用。
Chrome(`Chrome-Stub` + `Chrome.apk.gz`,依赖同样是占位 + 压缩包的 `TrichromeLibrary`)是同样的机制,但在本机上是正常的(用户确认),
所以解压机制本身没坏,问题只出在 WebView 这一个包上。具体原因还没从日志确认。

## 做法

用用户提供的完整独立版(standalone)WebView APK(`WEBVIEW_APK`,`conf.d/webview.conf`)换掉占位和压缩包,装成
`product/app/WebViewGoogle/WebViewGoogle.apk`,开机直接可用,不再依赖解压。

构建时核对:包名 `com.google.android.webview`;有 arm64 原生库;不依赖 Trichrome 静态库;`extractNativeLibs=false` 且原生库按 16KB 页对齐
(系统应用不解压原生库,直接从 APK 加载);签名和底包 WebView 占位一致(WebView provider 清单按签名认)。任一不满足就构建失败。

## 改动清单

- 删 `product/app/WebViewGoogle-Stub/`、`product/app/WebViewGoogle/`(含 `.apk.gz`)
- 加 `product/app/WebViewGoogle/WebViewGoogle.apk`(0644 root,`system_file`)

`TrichromeLibrary`、`Chrome` 的占位和压缩包不动。

## 保留数据刷机(user-v1.1 真机,2026-11-06)

user-v1.1 保留数据刷在 v1.0 上,WebView 在系统里但用不了,把同一个 APK 当更新装一遍就正常。原因不在本补丁:各版指纹相同,PackageManager 不当成系统升级,
沿用了 v1.0 时占位包的 ABI(空),原生库加载不了。已在 `identity/version-label` 里让每版的 `ro.system_ext.build.fingerprint` 不同来修(identity V1.4)。
已经刷了 v1.1 的机器:手动装一遍 `WEBVIEW_APK`,或者清数据。

## 验证

```bash
adb shell dumpsys webviewupdate | head
adb shell pm path com.google.android.webview
```
另外 `adb shell dumpsys package com.google.android.webview | grep -i abi` 的 `primaryCpuAbi` 应是 `arm64-v8a`(不能是 null)。
`Current WebView package` 应是 `com.google.android.webview`,路径在 `/product/app/WebViewGoogle/`。
