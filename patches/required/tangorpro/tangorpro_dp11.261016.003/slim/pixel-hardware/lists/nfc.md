# 清单 · nfc

## 做什么

删三项 NFC 相关的东西:`system_ext/priv-app/PixelNfc`、`priv-app/TagGoogle`、`product/overlay/NfcOverlayCommon.apk`。

## 原理

TB321FU 的 vendor 权限目录里没有 `android.hardware.nfc.xml`,说明没有 NFC 硬件。`PixelNfc` 是 Pixel 的 NFC 配置应用,`TagGoogle` 是读 NFC 标签的应用,`NfcOverlayCommon` 是 NFC 的资源覆盖。都用不上。

**只删应用和 overlay,不删 NFC 的 apex**(`com.google.android.nfcservices.apex`,约 7M)。我一开始想连 apex 一起删,看了内容发现它带着 `javalib/framework-nfc.jar`,这是启动类路径(`BOOTCLASSPATH`)上的 jar,`SystemServiceRegistry` 会在 zygote 预加载时引用它的类。删掉可能直接起不来。UWB 的 apex 同理,不删。(`slim/pixel-hardware/uwb` 删的是 Qorvo UWB 的应用和 overlay,也没碰 apex。)

没删 `SecureElement`(`app/SecureElement`):它是 OMAPI 的安全元件服务,体积才 1M,别的东西可能探测它。

## 改动清单

- 删上面三项。

## 输入 / 依赖

无。

## 换底包注意

别的 GSI 没有这些路径就跳过。

## 验证

`adb shell pm list packages | grep -iE "tag|nfc"`:没有 `com.google.android.tag`、Pixel NFC 配置;开机正常。
