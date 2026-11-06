# faceunlock/app — FaceUnlock.apk 和它的权限 xml

## 做什么

把人脸解锁的应用本体 `com.android.faceunlock`(ParanoidSense + 旷视 Megvii SDK,跑相机、做识别)放进 `system/priv-app`,并放好让它拿到权限所需的 4 份 xml。包名用 `com.android.faceunlock`(不是上游的 `co.aospa.sense`),避开把 `co.aospa.sense` 当作第三方 ROM 特征的检测。

不改 services.jar(那是 `faceunlock/services-hooks`),也不放设置里的入口(`faceunlock/settings-entry`)。

## 原理

`FaceUnlock.apk` 是个自签名 priv-app,里面的 `SenseService`(action `com.android.faceunlock.BIND`)被 system_server 里的 `SenseProvider` 绑定。4 份 xml 各管一件事:

| 文件 | 放在 | 作用 |
|---|---|---|
| `privapp_whitelist_com.android.faceunlock.xml` | `etc/permissions/` | priv-app 想拿 `signature\|privileged` 权限必须在白名单里:`SYSTEM_CAMERA`、`WRITE_SECURE_SETTINGS`、`SCHEDULE_EXACT_ALARM`、`MANAGE_BIOMETRIC`、`USE_BIOMETRIC_INTERNAL`。后两个在这台机器上其实是纯 `signature`,白名单给不了,靠 services-hooks 按身份放行;写进白名单是和上游保持一致 |
| `android.hardware.biometrics.face.xml` | `etc/permissions/` | 声明设备有 `android.hardware.biometrics.face` 这个 feature。设置等组件据此认为设备支持人脸(以 `hasSystemFeature` 为准,具体哪些地方读它没有逐个核对) |
| `hiddenapi-whitelist-com.android.faceunlock.xml` | `etc/sysconfig/` | 把 App 加入隐藏 API 白名单(App 里用了 `SystemProperties` 等非公开 API,例如读 `ro.face.sense_service.camera_id`) |
| `default_permissions_com.android.faceunlock.xml` | `product/etc/default-permissions/` | 默认授予 `CAMERA` 运行时权限(`fixed=false`,用户仍可撤销),录入时不用再弹授权 |

`priv-app/FaceUnlock/` 目录是模块自己建的(`put_dir`),并显式定标签 `u:object_r:system_file:s0`;新建目录不定标签会是 unlabeled。

## 改动清单

- **新增** `system/priv-app/FaceUnlock/`(目录 0755,标签 `system_file`)和里面的 `FaceUnlock.apk`。
- **新增** 4 份 xml(上表),都是 0644 root 属主、`system_file` 标签。
- 不改 `build.prop`:`ro.face.sense_service` 由 services-hooks 设(读它的是 services.jar 里的代码,App 不读)。

## 预编译件与第三方来源

- `files/FaceUnlock.apk` 是已构建好的 APK(MODULE-SPEC 允许放 `files/`)。源码和构建脚本在 `src/`(`src/build.sh`)。
- **旷视 Megvii SDK**(`libMegviiUnlock.so`、`libFaceDetectCA.so`、`libMegviiUnlock-jni-1.2.so`、`libmegface.so`、`vendorImplPrebuilt.jar`、模型文件)打在 APK 里(`lib/arm64-v8a/`、`res/raw/`),**来自 PixelOS ParanoidSense 上游**固定 commit `a500478bbb0e2933276d57796d9b410f0f8e90f8`(`github.com/PixelOS-AOSP/packages_apps_ParanoidSense`)。重建时 `src/fetch_upstream.sh` 会拉这个 commit;仓库里不放这些二进制。
- so 不压缩 + 页对齐放在 APK 里,`extractNativeLibs=false`,从 APK 直接加载(priv-app 下 so 不解压)。

## 重建 APK

镜像里装的是 `files/FaceUnlock.apk`,平时不用重建。真要重建:`bash src/fetch_upstream.sh` 拉上游,再 `bash src/build.sh <底包system> <输出目录>`。需要环境变量 `JAVA_HOME`(JDK 17)、`D2J`、`R8`(8.5.35)、`APKTOOL`、`BT`(build-tools 35:aapt2/zipalign/apksigner)、`KOTLIN_HOME`(kotlinc 2.0.21),签名 keystore 用 `FACEUNLOCK_KEYSTORE`(alias `faceunlock`,口令 `android`,不进仓库)。

注意 `build.sh` 借用了同组 `services-hooks` 的两样东西:AIDL stub 源码(`../../001.services-hooks/src/java/vendor`)和 `check_dex.py`。所以重建 App 时 `patches/required/tangorpro/tangorpro_graphene_2026110200/faceunlock/` 要整个在。只是**装**预编译 APK 不依赖它们。

设置里入口的 overlay 以前和 App 在同一个 `build.sh` 里编,现在拆到 `faceunlock/settings-entry/src/build.sh`。

## 输入

装预编译件不需要任何变量。重建 APK 才要上面那些环境变量(`FACEUNLOCK_KEYSTORE` 在 `conf.d/faceunlock.conf`)。

## 依赖和顺序

- 不依赖其他模块,可以放在 MODS 的任意位置。
- **单独启用的后果**(不带 services-hooks):App 和权限 xml 都装上了,feature 也声明了,但 system_server 里没有 `SenseProvider`,没人去绑 App 的 `SenseService`;就算有人调,`USE_BIOMETRIC_INTERNAL`/`MANAGE_BIOMETRIC` 的校验也没人放行。结果是人脸解锁用不了,App 在后台不会被启动,没有别的副作用。另外 `android.hardware.biometrics.face` feature 声明了,而系统里没有注册人脸传感器;feature 和传感器对不上时设置的表现没有实测,建议三个模块一起开,或都不开。
- 带 services-hooks、不带 settings-entry:设置里的录入流程没有被指向 App 的 `EnrollActivity`(`config_face_enroll` 没覆盖),用不了 App 的录入界面。

## 适用范围和换底包注意

`FaceUnlock.apk` 一般不用跟着换底包重建(只用底包的 framework-res.apk 当 link 资源、framework.jar 当 classpath)。底包的权限 protection 变了(例如 `USE_BIOMETRIC_INTERNAL` 变成 `signature|privileged`)时,需要重新核对 services-hooks 的放行是否还必要。

## 踩过的坑(带版本)

- **应用进程没有 kotlin-stdlib、也没有 services.jar**(v1):Kotlin 标准库、AIDL stub、vendorImplPrebuilt.jar 必须编进 APK 的 dex。
- **改包名踩的两个坑**(V2,见 `paranoidsense-gsi-port` 的 commit):旷视 `vendorImplPrebuilt.jar` 的 `FacePPImpl` 硬编码引用 `co.aospa.sense.util.PreferenceHelper/Constants`,所以 `util/` 子包保持 `co.aospa.sense.util.*` 不改名;旷视按包名查 res/raw,所以 aapt2 link 用 `--rename-manifest-package` 改 appId、manifest 里 `package=` 保持旧名、activity/service 写全类名。
- **CAMERA foreground-only**(v4→v5):要 `SenseProvider` 绑定时带 FOREGROUND flag 才能一直有相机权限,改的是 services-hooks,不是 App。
- **d8 不能加 `--no-desugaring`**:见 services-hooks 的 README,App 的 `build.sh` 同样用 desugar,并跑 `check_dex.py`。

## 验证

离线(已在 V66 底包上验证):`FaceUnlock.apk` 和 4 份 xml 与 V66 逐字节相同,`priv-app/FaceUnlock` 目录和文件的标签是 `u:object_r:system_file:s0`。

上机:
```bash
adb shell pm list packages | grep faceunlock   # com.android.faceunlock
adb shell pm list features | grep biometrics.face
adb shell dumpsys package com.android.faceunlock | grep -A3 "granted=true" # CAMERA 已授予
```
