# diag-boot-camera-log — 开机时记下相机驱动的日志(诊断用)

## 为什么要

联想相机的微距是 2 号相机。本系统上相机 HAL 只报 0、1 号。原厂和本系统用的是同一套 vendor、内核、boot,HAL 自己决定报几个相机,依据是开机时探测到哪些传感器。探测发生在开机十几秒,内核日志是环形缓冲,两分钟后那几行就没了,事后 `dmesg` 抓不到(2026-10-31 测试方抓的最早一条已经是开机 112 秒)。

## 做什么

`post-fs-data` 时启动一个一次性服务(herald 域),记 150 秒:
- `kmsg.txt`:`dmesg -w`,先输出缓冲里已有的全部内核日志,再跟着记新的;
- `logcat.txt`:`logcat -b all`,只留含 `CamX|CHIUSECASE|camera|sensor|probe|macro` 的行。

都在 `/data/local/tmp/tb321fu-bootlog/`,0644,adb 直接能拉。每次开机覆盖上一次的。

## 用法(cmd.exe)

```bat
adb reboot
adb wait-for-device
timeout /t 170
adb pull /data/local/tmp/tb321fu-bootlog
```

看 `kmsg.txt` 里 `CAM-SENSOR` 的 `Probe success` / `probe failed` 和传感器名(`kirby_txd_*`、`kirby_lce_sc202cs_macro` 等),`logcat.txt` 里 CamX 的报错。

## 依赖

`require_mod required/general/herald-core`(用它的 herald 域)。默认不打(在 `MODS_OFF` 里),查问题时 `WITH=diag-boot-camera-log` 构建。
