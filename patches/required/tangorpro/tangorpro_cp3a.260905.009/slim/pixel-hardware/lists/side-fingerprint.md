# 清单 · side-fingerprint — 侧边指纹 overlay

## 做什么

删掉 SfpsOverlayTablet、GoogleConfigSideFpsOverlay、BiometricTangorproOverlay 三个 overlay。

## 原理

Pixel Tablet 的指纹传感器在电源键上(侧边指纹,SFPS)。TB321FU 没有指纹。这三个 overlay 只是指纹录入/验证界面的文字和动画资源(覆盖到 SystemUI/Settings 上),并没有驱动功能,所以删了没副作用。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

三项在这套 Mystic 底包里都在,是 `product/overlay` 下的 apk 文件(不是目录)。注意:这一项不碰面部解锁,面部解锁在 `faceunlock` 组。

## 验证

设置 → 安全 里没有指纹设置项(本来也没有硬件);`adb shell cmd overlay list | grep -i fps` 为空。
