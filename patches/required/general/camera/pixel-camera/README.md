# pixel-camera — Pixel 相机(Google 相机 4.4)

## 做什么

把 Google 相机 4.4.020(`com.google.android.GoogleCamera`,Pixel 相机通用版,算法少、体积小,APK 约 24MB)装成 `system/app/GoogleCamera`。
`slim/pixel-leftovers` 的 google-camera 清单会删掉 GSI 自带的 Pixel 相机,所以不打这个补丁也不打联想相机的话,系统里没有相机应用。

## 原理

- APK 由用户提供(`PIXEL_CAMERA_APK`,默认 `inputs/apps/GoogleCamera-4.4.020.163412804.apk`,仓库里不放)。
- 系统应用没有安装过程,开机扫描 `/system/app` 时 PackageManager 直接用 APK 旁边 `lib/arm64/` 里的原生库,所以补丁把 APK 里 `lib/arm64-v8a/*.so` 解出来放过去(17 个,最大的 `libgcam.so` 约 10MB)。
- 不改相机服务,不改相机 HAL。用户 2026-11-01 在真机上装过同一个 APK:去掉联想相机补丁(固定设 HAL 客户端属性那个)之后 Pixel 相机正常。

## 改动清单

- `system/app/GoogleCamera/GoogleCamera.apk`(0644,`system_file`)
- `system/app/GoogleCamera/lib/arm64/*.so`

## 输入

| 变量 | 说明 |
|---|---|
| `PIXEL_CAMERA_APK` | Google 相机 APK,包名必须是 `com.google.android.GoogleCamera`,有 arm64-v8a 库 |

## 依赖和顺序

- 不依赖其他补丁。排在 `pixel-leftovers` 后面(那边会删 GSI 自带的同名 Pixel 相机);底包里已经有 GoogleCamera 就停下。
- 和联想相机(`required/general/camera/zuicamera`)包名不同,可以一起装,桌面有两个相机图标。

## 适用范围和换底包注意

- 换 APK 版本:改 `PIXEL_CAMERA_APK`,包名对、有 arm64 库、SDK 不高于底包即可。
- 开机默认授予相机、麦克风、读写存储(`etc/default-permissions/default-permissions-com.google.android.GoogleCamera.xml`),位置不授予。默认授权只在系统第一次扫描到这个包、或系统版本升级时生效;保数据刷机时已经装过同名包的话,以原来的授权状态为准。

## 验证

打开相机能预览、拍照;`adb shell pm list packages | grep GoogleCamera` 有 `com.google.android.GoogleCamera`。
