# faceunlock/settings-entry — 设置里的人脸解锁入口

## 做什么

放一个静态 overlay `FaceUnlockSettingsOverlay.apk`(目标包 `com.android.settings`,priority 600),让设置的「人脸解锁」录入流程跳到我们的 App(`com.android.faceunlock/.activities.EnrollActivity`),并带上录入引导页用的文案和动画。

## 原理

Pixel 设置里人脸录入的流程是由 `res/values/config.xml` 的资源开关决定的。overlay 覆盖了这些:

- `config_face_enroll` = `com.android.faceunlock/com.android.faceunlock.activities.EnrollActivity`:点「设置人脸解锁」后启动的活动(厂商录入界面),指向 App。
- `config_face_education_use_lottie`=true:教育页用 Lottie 动画(`res/raw/face_education_lottie.json`、`face_settings.mp4`)。
  这两个素材是 Google 的 Pixel 设置资源,经 ParanoidSense 上游(`overlay/res/raw/`)提供,**不随仓库分发**;`src/build.sh` 构建时从 `fetch_upstream.sh` 拉下的上游取。
- `config_face_intro_show_less_secure`=true、`config_face_intro_show_require_eyes`=false:介绍页显示「安全性较低」说明,不显示「需要睁眼」。
- `res/values/strings.xml`:录入流程的英文文案(`security_settings_face_enroll_*`)。

`isStatic=true`,放在 `product/overlay/` 里开机就生效,不用 OverlayManager 启用。

## 改动清单

- **新增** `system/product/overlay/FaceUnlockSettingsOverlay.apk`(0644 root,`system_file` 标签)。APK 内含上面两个素材,**不进仓库**(已 gitignore),构建镜像前先用 `src/build.sh` 编到 `files/`。

## 源码和重建

- 源码:`src/overlay/`(`AndroidManifest.xml` + `res/`)。
- 构建脚本:`src/build.sh`(aapt2 compile/link → zipalign → apksigner),不依赖 App 源码,但要 ParanoidSense 上游的两个素材(先跑 `../002.app/src/fetch_upstream.sh`,或用 `PARANOIDSENSE_DIR` 指定上游目录)。以前它和 `FaceUnlock.apk` 在同一个 `build.sh` 里编,现在拆出来了。
  ```bash
  bash ../002.app/src/fetch_upstream.sh
  BT=<build-tools 35 目录> FACEUNLOCK_KEYSTORE=<keystore> bash src/build.sh <底包system> files/
  ```
  不给 keystore 会自动生成一个(静态 overlay 靠系统分区加载,换签名不影响使用)。
- 已验证:用这个脚本 + 原 keystore 重编出来的 APK,和原来入库的 `FaceUnlockSettingsOverlay.apk` 逐字节相同(改为从上游取素材前验证; 上游素材与原素材 SHA-256 相同)。

## 输入

`files/` 里已有本地编好的 APK 时不需要变量。编 APK 要 `BT`、可选的 `FACEUNLOCK_KEYSTORE`,以及 `fetch_upstream.sh` 拉下的上游素材(或 `PARANOIDSENSE_DIR`)。

## 依赖和顺序

- 不依赖其他模块,顺序任意。
- **单独启用的后果**:overlay 装上了,但没有 `com.android.faceunlock`(不带 `faceunlock/app`),或没有人脸传感器注册(不带 `faceunlock/services-hooks`),设置里要么看不到人脸入口,要么点进去启动不了录入活动(各种组合下设置具体怎么表现没有逐一实测)。没有别的副作用。要用人脸解锁,三个模块一起开。

## 适用范围和换底包注意

overlay 针对底包的 `com.android.settings` 里这些资源名(`config_face_enroll` 等)。换底包后 Settings 如果改了这些资源名,overlay 会静默不生效(aapt2 link 只对 framework-res 检查,不会报错),要上机确认设置里能进入录入流程。

## 验证

离线:APK 和 V66 逐字节相同(改为从上游取素材之前)。上机:
```bash
adb shell cmd overlay list | grep -i faceunlock   # 应该是 [x]
# 设置 → 安全 → 人脸解锁:点设置后进入我们的录入界面
```
