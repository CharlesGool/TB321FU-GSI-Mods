# 清单 · retail-demo — 零售演示

## 做什么

删掉 RetailCorePrebuilt 和 RetailDemoGooglePrebuilt。

## 原理

商店展示机的零售演示模式,正常用户用不到,常驻两个包。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

两项在这套 Mystic 底包里都在,都在 `product/priv-app`。

## 验证

设置里没有零售演示模式相关入口;`adb shell pm list packages | grep -i retail` 为空。
