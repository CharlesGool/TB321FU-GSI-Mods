# zuicamera/camera-id-check — 联想相机在没有 2 号相机的系统上不再闪退

## 问题

V71–V73 真机上一打开联想相机就闪退:`getCameraCharacteristics: Unable to retrieve camera characteristics for unknown device 2`。我们的系统里相机 HAL 只上报 0(后摄)和 1(前摄)。

## 原因(反编译原厂 ZuiCamera 得到)

- 相机编号按机型写死在 APK 里:`raw/camera_device_info`(资源名被混淆成 `res/Wi.json`),按 `Build.DEVICE` 匹配。TB321FU 这一条:`back_ids "0,2"`、`back_aux1 "2"`、`back_wide "2"`、`front_main "1"`。
- 启动时 `CameraDeviceInfo.checkIds(系统相机列表)` 把不存在的编号置成 `"-1"`,但**漏了 `back_wide` 和 `back_tele`**。
- 拍照模块 `CaptureModule.getAuxCameraIds()` 取 `back_wide`,还是 2,于是 `MultiBaseModule.updateCameraCharacteristics()` 去查 2 号相机 → 闪退。
- 原厂系统里这个问题被掩盖了:原厂 HAL 会多报一个相机(vendor 里的传感器有 `kirby_lce_sc202cs_macro`,2MP 微距),原厂 `framework.jar` 的高通版 `CameraManager` 只把 2 号及以后的相机给 `vendor.camera.aux.packagelist` 里的应用看。

## 做法

在 `checkIds()` 开头插入两段核对:`back_wide`、`back_tele` 不在系统相机列表里就置成 `"-1"`(和其余字段一样)。

- 用 `toolkit/lib/apk-smali.sh`(apktool 2.12.1 只解 dex、回编后只换改过的 dex、zipalign、重签)跑 `files/patch_checkids.py`,改 `CameraDeviceInfo.smali`。
- 系统预装应用不要求特定签名,权限白名单按包名给。已装过原版的设备第一次开机,系统会按新签名重新扫描这个系统应用,数据保留。

有 2 号相机的系统上,编号存在就保留,行为和原版一样。所以以后 HAL 真把广角/微距暴露出来,这个补丁不用撤。

## 效果和限制

- 能打开相机,主摄和前摄能用;没有 2 号相机时,广角/微距切换不可用。
- 为什么我们的系统上 HAL 少报一个相机还没查清。原厂的 `libcameraservice.so` 是联想改过的,会设 `vendor.lenovocamera.packagename.{zui,client,camera0.client,camera1.client}`,vendor 的 `init.target.rc` 转成 `vendor.camera.packagename.*`,camx(`camera.qcom.so`、`com.qti.chi.override.so`、`camx.device-impl.so`)读这些属性;没确认它们是否影响相机数量。

## 依赖

`require_mod zuicamera/app`(改的就是它装进去的 APK),所以要排在它后面。需要 `java`、`zipalign`、`apksigner`、`python3`,以及 `APKTOOL_JAR`(device.conf 里已有)。

## 验证

```bat
adb logcat -c
adb shell am start -n com.zui.camera/.CameraLauncher
adb logcat -d -s AndroidRuntime CameraService > cam.log
```
不再有 `unknown device 2`,能看到取景画面。
