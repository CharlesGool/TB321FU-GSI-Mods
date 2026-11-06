# 清单 · uwb — UWB

## 做什么

删掉 Qorvo UWB 服务(UwbVendorService)、它的权限 xml(`privapp-permissions-qorvo.xml`)和 overlay(UwbOverlayT6pro)。

## 原理

TB321FU 没有 UWB 硬件。UwbVendorService 是常驻服务,找不到 HAL(日志 "HAL is unavailable"),**每 19 秒崩一次**。权限 xml 和 overlay 是它的配套。V3 起删除。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

三项在这套 Mystic 底包里都在(服务在 `system_ext/priv-app`,权限在 `system_ext/etc/permissions`,overlay 在 `product/overlay`)。

## 验证

`adb logcat -b crash -d | grep -i uwb` 不再有反复崩溃;`adb shell pm list packages | grep -i uwb` 为空。
