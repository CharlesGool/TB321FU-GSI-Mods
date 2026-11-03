# brightness/display-config

## 做什么

把原厂 `vendor/etc/displayconfig/display_id_*.xml`(面板的"亮度 → 尼特"表)复制一份到 `/product/etc/displayconfig/`,只改一处:HBM 的 `<minimumLux>` 改成 0。结果:手动拉满不要求强光就能到面板峰值 782 尼特,但**保留原厂时间限制**(30 分钟窗口里最多 5 分钟,剩余不足 1 分钟不再进)。

## 原理

Android 15 的 `DisplayDeviceConfig` 先找 `/product/etc/displayconfig/`,再找 `/vendor/etc/displayconfig/`。真机现象:不放这份时自动亮度最低只能降到 40% 左右;放了(此前是靠"HBM 不限时"带进来的)就正常。所以怀疑 GSI 没有真正用到 vendor 里那份,自动亮度曲线(单位是尼特)没法正确换算成亮度。这里无条件放一份;除 `<minimumLux>` 外和 vendor 一字不差。

可选补丁 [hbm-unlimited](../../../../../../optional/brightness/hbm-unlimited/) 排在本补丁后面,把同名文件换成连时间限制也去掉的版本。

## 改动清单

- 加 `product/etc/displayconfig/display_id_*.xml`(0644 root:root `system_file`)。

## 输入 / 依赖

`STOCK_VENDOR_IMG`(原厂 vendor 镜像)。

## 换底包注意

换原厂固件会自动用新固件里的 xml。

## 验证

不打 hbm-unlimited:自动亮度在暗处应能降到约 8 尼特(远低于 40%);室内手动拉满约 782 尼特,持续一段时间(最多约 5 分钟)后被压回约 741 尼特。`adb shell dumpsys display | grep -i nits` 看尼特表是否来自这份。**没有真机验证**,原因是推测。
