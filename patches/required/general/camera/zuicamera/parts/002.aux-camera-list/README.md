# zuicamera/aux-camera-list — 辅助镜头的包名清单

## 做什么

让 `vendor.camera.aux.packagelist` 的值和原厂一致:包含 `com.zui.camera`。

## 原理

原厂 `system/build.prop` 里有 `vendor.camera.aux.packagelist=org.codeaurora.snapcam,com.yha.factory,com.motorola.motocit,com.zui.camera`,看名字是列出能使用辅助镜头的应用包名。GSI 的 build.prop 没有这一条。这个属性被谁读、怎么读,我没有读 vendor HAL 去证实,这里的做法只是和原厂保持一致。

值不写死:构建时从 `STOCK_SYSTEM_IMG` 的 `system/build.prop` 现取,原厂值里没有 `com.zui.camera` 就报错。

## 改动清单

`system/build.prop`:新增(或改写)一行 `vendor.camera.aux.packagelist=…`。

## 输入

`STOCK_SYSTEM_IMG`。

## 依赖和顺序

- 不依赖其他模块;和 `zuicamera/app` 谁先谁后都行。
- 只开这一个:多一条属性,没有别的效果。

## 适用范围和换底包注意

换原厂固件后,属性名或值变了会在构建时失败(找不到属性,或值里没有 `com.zui.camera`),按新固件核对。

## 踩过的坑

暂无。

## 验证

```bash
adb shell getprop vendor.camera.aux.packagelist
```
应是 `org.codeaurora.snapcam,com.yha.factory,com.motorola.motocit,com.zui.camera`。有没有实际效果(广角等镜头是否对联想相机开放)要在相机里切镜头确认。

## V72 补充:V71 真机联想相机闪退的处理(未验证)

V71 真机:联想相机闪退,`getCameraCharacteristics: Unable to retrieve camera characteristics for unknown device 2`(系统只有相机 0、1),`adb shell getprop` 读这个属性是空。
这个属性在 `vendor_property_contexts` 里只被 `vendor.` 前缀标成 `vendor_default_prop`;GSI 的 cameraserver 没有读 `vendor_default_prop` 的权限,shell 也读不到,所以 `getprop` 为空不能证明没设。V72 加了两处:
- `etc/init/tb321fu-camera-aux.rc`:`post-fs-data` 里 `setprop` 一次(值与 build.prop 相同)。
- SELinux:`allow cameraserver vendor_default_prop (file (read open getattr map))`。

**这两处都是推测性修复,没有真机日志坐实。**如果还是闪退,请抓:`adb shell dumpsys media.camera > cam.txt`(看里面的相机 ID 列表)、`adb logcat -d -s CameraService > cam.log`、`adb logcat -d -b events | findstr avc` 里和 camera 相关的拒绝。
