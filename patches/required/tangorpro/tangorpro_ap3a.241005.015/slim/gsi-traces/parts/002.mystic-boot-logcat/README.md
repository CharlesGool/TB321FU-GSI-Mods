# slim/gsi-traces/mystic-boot-logcat

## 做什么

删 `etc/init/mystic.rc`。

## 原理

`mystic.rc` 在 `post-fs-data` 里删掉 `/data/boot_lc_main.txt`,然后启动服务 `boot_lc_main`:`/system/bin/logcat -f /data/boot_lc_main.txt`,以 root(`user root`、`group root system`)运行。这是 Mystic 开机调试用的:每次开机在 /data 里留一份 root 属主的 logcat 文件,白占资源,还多一个 GSI 特征。成品用不到。

## 改动清单

- 删 `etc/init/mystic.rc`。

## 输入 / 依赖

无。

## 换底包注意

别的 GSI 没有就跳过。

## 验证

`adb shell ls /data/boot_lc_main.txt` 不存在;`adb shell getprop init.svc.boot_lc_main` 为空。
