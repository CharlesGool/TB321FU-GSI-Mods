# zuicamera/real-device-id — 全局伪装下联想相机仍看到真实机型

## 问题

V74 真机:全局伪装开着(设备名 tangorpro)时,联想相机一启动就崩,堆栈在 `ModeRecyclerView`;关掉全局伪装就正常。

## 原因

全局伪装(`spoof/global-pif`)在开机早期用 resetprop 全局改 `ro.product.{brand,device,manufacturer,model,name}`,所以所有应用的 `android.os.Build.DEVICE` 都是 `tangorpro`。相机到处按 `Build.DEVICE` 分支:
- `CameraDeviceInfo` / `AppFeatures` 按它在 `res/Wi.json` 里找本机的相机配置(TB321FU 条目),找不到就没有配置;
- `ApiHelper.IS_KIRBY = "TB321FU".equals(Build.DEVICE)` 等机型开关;
- `ModeRecyclerViewAdapter`、`VfbPlatformSettings`、`AlgoUtils`、`ExifUtil` 也读 `Build.DEVICE/MODEL`。

全局伪装不是按应用挂钩子,没法"豁免某个应用"。

## 做法

用 `toolkit/lib/apk-smali.sh` 跑 `files/patch_real_build.py`:
- 加一个类 `com.zui.camera.TbRealBuild`,`device()/model()/brand()/manufacturer()/product()` 依次读 `ro.product.vendor.*`、`ro.product.system.*`(全局伪装不改这两组,SELinux 上所有应用都能读:`build_vendor_prop`、`build_prop`),都读不到才用 `Build.*`。
- 把相机自己代码(`com/zui/camera/` 下)所有 `sget-object Landroid/os/Build;->DEVICE|MODEL|BRAND|MANUFACTURER|PRODUCT` 换成调用它(原厂 APK:7 个类 31 处)。第三方库(webrtc、material、lenovo dolphin 日志)不动。
- 只改 dex,资源/lib 不动,APK 重签。

全局伪装关着时读到的值和 `Build.*` 相同(`ro.product.vendor.device/model` = TB321FU)。照片 EXIF 里的厂商/型号也会是真实的 LENOVO / TB321FU,不是伪装的。

## 依赖

`require_mod zuicamera/app`;和 `zuicamera/camera-id-check` 互不依赖,两个都开时各打各的补丁(顺序随意)。需要 `java`、`zipalign`、`apksigner`、`python3`、`openssl`、`unzip` 和 `APKTOOL_JAR`。

## 验证

开着全局伪装(`heraldctl spoof get` 末尾 `HERALD_GLOBAL_PIF_FLAG=on`)重启后打开联想相机,能进取景界面;`adb logcat -d -s AndroidRuntime` 没有 `ModeRecyclerView` 的崩溃。
