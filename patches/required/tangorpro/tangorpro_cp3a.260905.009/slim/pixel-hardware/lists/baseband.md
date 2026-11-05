# 清单 · baseband — Pixel 基带

## 做什么

删掉 grilservice(Google RIL 扩展服务)和 ConnectivityThermalPowerManager(基带温控)。

## 原理

TB321FU 是纯 WiFi 版,没有基带。grilservice 是 Pixel 基带 RIL 的 Google 扩展,常驻;ConnectivityThermalPowerManager 管基带的温控/功耗。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

两项在这套 Mystic 底包里都在,都在 `system_ext/priv-app`。如果以后换成有基带(蜂窝版)的机型,这个模块要关掉。

## 验证

`adb shell pm list packages | grep -iE "grilservice|connectivitythermal"` 为空。
