# zui_camera — 联想原厂相机(ZuiCamera)

> 一个补丁(`zuicamera`),内部 5 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`zuicamera`),内部 5 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

## 解决什么问题

`slim/pixel-leftovers` 的 google-camera 清单 删掉了 Pixel 的相机,系统里就没有相机应用了。这一组把联想 ZUI 自带的相机(`com.zui.camera`)装回来:它跑的是 TB321FU 原厂 vendor 里的相机 HAL,美颜、人像虚化、自动取景、专业模式这些算法都打在 APK 自己里面,不依赖系统里的 ZUI 框架。

**只装相机应用,不动相机服务**(`cameraserver`、`libcameraservice.so` 都是 GSI 自带的)。联想的 CameraPandora 是改在 `libcameraservice.so` 里的,作用对象是第三方视频通话应用(微信、Zoom、Teams 等)的前置摄像头美颜和自动取景,和 ZuiCamera 自己的功能无关,本组不包含。

## 模块

| 部分 | 做什么 | 能不能单独关 | 运行时开关 |
|---|---|---|---|
| [`app`](parts/001.app/README.md) | 从原厂 system 镜像取 ZuiCamera.apk,放进 `priv-app`,配权限白名单、sysconfig 和 feature 声明 | 能 | 无 |
| [`aux-camera-list`](parts/002.aux-camera-list/README.md) | `vendor.camera.aux.packagelist` 加上 `com.zui.camera`(值从原厂 build.prop 现取) | 能 | 无 |
| [`camera-id-check`](parts/003.camera-id-check/README.md) | 修相机应用的编号核对(漏了 `back_wide`/`back_tele`),系统没有 2 号相机时不再闪退;APK 重签 | 能(关了在本系统上一打开就闪退) | 无 |
| [`real-device-id`](parts/004.real-device-id/README.md) | 相机读机型改成读 `ro.product.vendor.*`/`system.*`,全局伪装开着时也看到 TB321FU,不再崩;APK 重签 | 能(关了在全局伪装下一启动就崩) | 无 |
| [`hide-unsupported`](parts/005.hide-unsupported/README.md) | 屏蔽依赖缺失组件的功能:模式栏去掉互联录制和微距,许可/隐私链接点了不再闪退;APK 重签 | 能 | 无 |
| [`memory-check`](parts/007.memory-check/README.md) | 拍照前"内存已满"判断改按真实已用量(`max-(total-free)`);A17 上原判断恒为满,快门没反应(2026-11-06 DP11 真机);APK 重签 | 能(关了在 A17 上拍照基本没反应) | 无 |

## 顺序和依赖

- `app` 和 `aux-camera-list` 互不依赖;`camera-id-check`、`real-device-id`、`hide-unsupported` 改的是 `app` 装进去的 APK,要排在 `app` 后面,三者之间顺序随意(都用 `toolkit/lib/apk-smali.sh` 打补丁)。
- 只开 `app`:相机能装能跑,辅助镜头(广角等)是否对它开放取决于 vendor 是否按包名放行,没有实测。
- 只开 `aux-camera-list`:只多一条属性,没有相机应用,没有别的效果。
- 和 `slim/pixel-leftovers` 的 google-camera 清单 互不影响:不开 `slim/pixel-leftovers` 的 google-camera 清单 时 GSI 自带的 Pixel 相机和 ZuiCamera 会同时存在,桌面有两个相机图标。

## 没带的东西

| 东西 | 为什么没带 |
|---|---|
| `ZuiCameraAssistant`(悬浮助手,要 `SYSTEM_ALERT_WINDOW`、`WRITE_SECURE_SETTINGS`) | ZuiCamera 本体没有引用它的包名,不是拍照必需的 |
| `ZuiCameraQR`(独立扫码入口) | 同上;ZuiCamera 自己有 `SmartScannerActivity` |
| `com.zui.camera.google.lens.feature.xml`、`ro.com.google.lens.oem_camera_package` | 声明了 Google Lens 联动,而 GSI 里没有 Google 应用,装了只会多一个点了没反应的入口 |
| CameraPandora(`libcamerapandora`、`libpandora*`、`libmorpho_*`、原厂 `libcameraservice.so`) | 要换掉整个 cameraserver,SELinux 和 ABI 风险大,收益只在第三方视频通话应用里。以后要做另开 `zui_camera/pandora` 模块 |
| `ro.config.lgsi.*` 属性(`lgsi_prop.cfg` 从 odm 属性派生) | 应用读不到时走默认值;区域相关的行为(隐私协议页等)是否受影响没有实测 |

## 空间

镜像是固定大小的分区。`ZuiCamera.apk` 约 213MB,erofs(lz4hc)压缩后约 167MB。V67 余量约 285MB,Tango 约占 37MB,这一组装进去后余量大约 80MB。余量不够时构建在 AVB 重签那步失败(镜像比分区大)。

## 整组独立发布时要带什么

`patches/required/general/camera/zuicamera/` 加 `toolkit/`。不放 APK:两个模块都从 `STOCK_SYSTEM_IMG`(原厂 ZUI system 镜像)现取,用户自己提供。

## 版本

V68 起加入 `MODS`。已在干净 GSI 底包上单独构建通过(`test-modules.sh --solo`);**还没有在平板上实测**,实测清单见 [`app/README.md`](parts/001.app/README.md) 的"验证"。

## 第三个摄像头(2 号,微距)

**硬件有,内核也探测到了,是相机 HAL 在 GSI 模式下把它藏了。** 修法见 [`macro-camera-fix`](../../required/general/hardware-fix/macro-camera-fix/README.md)。

- 2026-10-31 测试机开机内核日志:`Probe success for kirby_txd_ov13b10_main slot:0`、`kirby_txd_sc820cs_front slot:1`、`kirby_lce_sc202cs_macro slot:2`(主摄、前摄是 TXD 模组,微距是 LCE 的 sc202cs;同一 slot 上另一家的传感器 `Probe failed` 是正常的多供应商探测)。
- HAL 只报 0、1 的原因:`com.qti.chi.override.so` 调 `isRunningWithVendorEnhancedFramework()`(`libqti_vndfwk_detect.so`,= 读 `ro.vendor.qti.va_aosp.support`),为假就把多摄配置换成 `lanai_gsi.xml`,只暴露主摄和前摄。原厂 system 的 `build.prop` 里有 `ro.vendor.qti.va_aosp.support=1`,GSI 没有。
- 原厂的调用链:联想相机微距模式(`MacroCaptureModule`)直接打开 `back_aux1` = 2 号相机;原厂高通版 `CameraManager` 只把 2 号以后的相机给 `vendor.camera.aux.packagelist` 里的应用(本系统 AOSP 框架不过滤,所有应用都看得到)。联想 cameraserver 设的 `vendor.lenovocamera.packagename.*` 只影响 HAL 的 3A 热启动和联想节点(水印等,见 `hal-client-props`),不决定相机数量。

抓开机日志(cmd.exe;`diag-boot-camera-log` 装了的话直接 `adb pull /data/local/tmp/tb321fu-bootlog`):
```bat
adb shell heraldctl rexec on 30
adb shell heraldctl rexec grep -i -e probe -e slot -e kirby -e sc202cs -e macro /dev/kmsg > boot-sensor.txt
```
开机后尽快跑(内核日志是环形缓冲,两分钟左右探测记录就被冲掉);别用 PowerShell 的 `>`(存成 UTF-16,`findstr` 搜不到)。

## 去掉 hal-client-props(2026-11-01)

原来有一个部分开机把 `vendor.lenovocamera.packagename.*` 固定设成"客户端 = 联想相机",让相机 HAL 的联想节点认出联想相机,水印才生效。
这些属性是全局的,其他相机应用打开相机时 HAL 也会当成联想相机,可能让它们不能正常使用,所以去掉了。代价:联想相机的水印不再生效(其他拍照功能不受影响)。
要恢复水印,得让这几个属性只在联想相机打开相机时设,而不是开机固定;还没做。

## 改全局机型的影响

联想相机要读真实机型。改全局机型(全局伪装等)会让它无法使用;`real-device-id` 只是让它在本项目的全局伪装下仍读到 TB321FU,别的改机型方式不保证。需要改机型的用户请不要选联想相机。

## 默认授权(2026-11-01)

联想相机 target SDK 34,启动时检查 `READ/WRITE_EXTERNAL_STORAGE`,而这两项在 Android 13 以后的设置里没有开关,用户没法授予,于是弹"缺少运行所需的必要权限"
(V102 真机:相机服务里没有它的连接记录,应用里只有这两项未授权,adb 授权后正常出画面、能存照片)。
`001.app` 现在多装一份 `etc/default-permissions/default-permissions-com.zui.camera.xml`,开机默认授予相机、麦克风、读写存储和 `READ_MEDIA_IMAGES`;位置不授予。
默认授权只在系统第一次扫描到这个包、或系统版本升级时生效。从没有联想相机的版本(如 user-v1.3)保数据刷过来,指纹没变、包又是新装的,默认授权不会跑,
相机照样弹"缺少运行所需的必要权限"(user-v1.3-zuicamera 真机问题,手动 `adb shell pm grant com.zui.camera android.permission.READ_EXTERNAL_STORAGE` 后正常)。
所以 `006.storage-permission` 直接改相机应用,让它不再检查这两项(见该部分的 README),清数据也不受影响。
