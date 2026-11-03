# slim/old-vndk

## 做什么

只保留原厂 vendor 要用的那一个 VNDK apex,删掉其余版本。TB321FU 的 vendor 是 `ro.vndk.version=34`,删掉 `com.android.vndk.v30`、`v31`、`v32`、`v33` 四个,共约 246M(v30 一个就 114M)。

## 原理

VNDK(Vendor NDK)是 vendor 分区可以依赖的一小组系统库。Android 把它做成 apex(`com.android.vndk.vNN`),GSI 要能配各种 vendor,就把 v30 到 v34 全带上。vendor 只链接它自己那个版本,linkerconfig 也只按 `ro.vndk.version` 挑一个,其余几个没人用。

这些 apex 里没有启动类路径的 jar(`javalib` 目录不存在),所以删掉不影响 `BOOTCLASSPATH`/`SYSTEMSERVERCLASSPATH`,不像 NFC/UWB 的 apex 那样删不得。

保留哪个版本不是写死的:模块挂载原厂 vendor 镜像,读它的 `ro.vndk.version`。读不出来、或者底包里没有这个版本的 apex,就直接失败,不会去删别的。

## 改动清单

- 删 `apex/com.android.vndk.v30.apex`、`v31`、`v32`、`v33`(对 TB321FU)。

## 输入(device.conf)

| 变量 | 说明 |
|---|---|
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像,用来读 `ro.vndk.version` |

## 依赖和顺序

无依赖,和别的模块无关。

## 换底包注意

- 换原厂固件(vendor 的 VNDK 版本变了,比如升到 35):自动跟着变,保留新版本。底包里没有这个版本的 apex 就失败。
- 换 GSI 底包:只删它带的、不是 vendor 版本的 VNDK apex。
- `phh-on-boot.sh` / `phh-on-data.sh` 里对 `com.android.vndk.v28` 的引用只在 vendor 是 vndk 27/28 时才走,我们不走。

## 踩过的坑

没有。**没有在真机上试过**,删旧版 VNDK 是 GSI 瘦身的常见做法,但这个镜像还没刷过。刷后看 `adb shell ls /apex | grep vndk` 只剩 v34,并确认能正常开机、Wi-Fi/蓝牙/相机正常。

## 验证

```bash
adb shell ls /apex | grep vndk       # 只有 com.android.vndk.v34
adb shell getprop ro.vndk.version    # 34
```
