# 清单 · hbm-uv — 强光模式 / UV 统计

## 做什么

删掉 HbmSVManager、它的两个 JNI 库(`libhbmsvmanager_jni.so`,32 位和 64 位各一个)和 UvExposureReporter。

## 原理

Pixel 屏幕专用:HbmSVManager 管强光模式(HBM,高亮度模式)的监督,常驻;UvExposureReporter 统计屏幕的 UV 老化。TB321FU 的屏幕和驱动都不是 Pixel 的,这两个服务用不到,常驻还会去找 Pixel 的接口。JNI 库是 HbmSVManager 的,服务删了库就没人加载。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

四项在这套 Mystic 底包里都在,全在 `system_ext` 下(`priv-app/` 和 `lib/`、`lib64/`)。

## 验证

`adb shell dumpsys activity services | grep -iE "hbm|uvexposure"` 为空。
