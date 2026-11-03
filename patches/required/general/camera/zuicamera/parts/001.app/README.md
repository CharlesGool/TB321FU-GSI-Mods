# zuicamera/app — 联想相机本体和它的权限文件

## 做什么

把原厂 ZUI 相机 `com.zui.camera` 装成 `system/priv-app/ZuiCamera/`,并放好让它启动、拿到权限所需的三份 xml。装完桌面有"相机"图标。

## 原理

ZuiCamera 是普通 priv-app(没有 sharedUserId,没有 `uses-library`),目标 SDK 34,在 A15 上可以直接跑:

- 联想的界面框架 `zui.*`(279 个类)、美颜(`libFNVfbEngine*`)、虚化(`libBST*`)、自动取景(Morpho GPU 处理)、TFLite 等都在 APK 里,`extractNativeLibs=false`,so 从 APK 直接加载。
- 相机采集走 Camera2,厂商标签(`com.lenovo.camera.*`、`org.codeaurora.qcamera3.*`)由原厂 vendor 的相机 HAL 提供,我们的 vendor 就是原厂的。
- 引用的 `android.*` 类逐个核对过,GSI 的 framework 里都有(只有 `IExWifiManagerService` 是联想的,应用自己带了定义)。这是静态检查,类里的方法没核对。

三份 xml,都是原厂原文:

| 文件 | 放在 | 作用 |
|---|---|---|
| `privapp-permissions-com.zui.camera.xml` | `etc/permissions/` | priv-app 要拿 `signature\|privileged` 权限必须在白名单里:`WRITE_MEDIA_STORAGE`、`WRITE_SECURE_SETTINGS`、`REAL_GET_TASKS`、`BIND_WALLPAPER`、`STOP_APP_SWITCHES`、`STATUS_BAR`、`INTERACT_ACROSS_USERS` |
| `com.zui.camera.record.inter.connection.xml` | `etc/permissions/` | 声明 feature `com.zui.camera.record.inter.connection`(应用据此启用录屏联动一类的入口,具体读法没有逐个核对) |
| `initial-stopped-states-com.zui.camera.xml` | `etc/sysconfig/` | 首次安装时包不是"已停止"状态,开机后能收到广播 |

## 改动清单

- **新增** `system/priv-app/ZuiCamera/`(0755,`system_file`)和 `ZuiCamera.apk`(0644)。
- **新增** 上表三份 xml(0644,`system_file`)。
- 不改任何已有文件。

## 输入

`device.conf` 的 `STOCK_SYSTEM_IMG`(原厂 ZUI system 镜像;当前是 ZUI 17.0.12.044 OPEN ROW,里面的 ZuiCamera 是 17.0.2.250609115111)。需要 `aapt`。

## 依赖和顺序

- 不依赖其他模块,顺序随意。
- 底包里已经有 `system/priv-app/ZuiCamera` 时构建失败(不重复装)。

## 适用范围和换底包注意

- 换原厂固件:三个文件名在新固件里变了会在"原厂镜像里没有"处失败,核对文件名即可。APK 包名不是 `com.zui.camera`、要求的 SDK 比底包高也会失败。
- 换 GSI 底包:如果新底包的 platform 对 `INTERACT_ACROSS_USERS` 等权限的保护级别变了,白名单不够用时应用会缺权限;首启动先看 `logcat | grep -i privileged`。

## 没有带的联动(缺了不影响拍照)

相册 `com.zui.gallery`(库存里本来就没有)、AI 识图 `com.zui.ai.lens`、`com.zui.ai.aiservice`、`com.lenovo.menu_assistant`、`com.lenovo.lenovoprivacy`(首次启动的隐私协议)。对应的自定义权限(`zui.permission.READ_RESOLVER`、`com.zui.gallery.permission.*` 等)也拿不到。预期是这些入口点了没反应,首次启动的隐私协议页的表现没有实测。

## 踩过的坑

暂无(还没上机)。

## 验证

离线:构建日志里有"原厂 ZuiCamera 17.0.2…"和四条 `+ system/…`;三个目录和文件标签是 `u:object_r:system_file:s0`。

上机(**需要实测的清单**):
```bash
adb shell pm list packages | grep com.zui.camera          # 在不在
adb shell dumpsys package com.zui.camera | grep -E "codePath|granted=true|privatePkgFlags"
adb shell cmd package resolve-activity -c android.intent.category.LAUNCHER com.zui.camera
adb logcat -b all | grep -i -E "privileged permission|avc: denied.*(zui|camera)"   # 白名单和 SELinux
```
然后打开相机:能取景、拍照、录像、切前后摄、美颜和人像能开;首次启动的隐私协议页有没有卡住;点缩略图会不会闪退。
