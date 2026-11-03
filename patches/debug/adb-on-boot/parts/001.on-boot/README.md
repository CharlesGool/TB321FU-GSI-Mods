# on-boot — 开机 ADB 自启动

`system/build.prop` 加 `persist.sys.usb.config=adb,mtp`:开机就启用 ADB,不用先去开发者选项里手动打开。

`debug-off` 删掉 Mystic 调试段时把这一行一起删了,本部分把它加回来。`persist.*` 用户在设置里改过的以用户的为准,这里只是出厂默认。不动安全属性。

没上真机验证:刷机后 `adb devices` 应在开机后直接可见。
