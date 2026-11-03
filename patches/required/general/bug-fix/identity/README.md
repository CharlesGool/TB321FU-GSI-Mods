# identity — 机型身份

> 一个补丁(`identity`),内部 3 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

## 解决什么问题

GSI 底包是 Pixel Tablet(`google/tangorpro`)的 Android 15,还带着 Mystic 加的调试开关(`ro.debuggable=1`、`ro.secure=0`、强开 ADB)。要让装完的系统认自己是 Lenovo TB321FU、和真机一样不带 GSI/userdebug 的痕迹,得改三份 build.prop(`system/build.prop`、`system/product/etc/build.prop`、`system/system_ext/etc/build.prop`)。这一组把它拆成互不相干的几处改动。

## 部分

| 部分 | 做什么 |
|---|---|
| [001.product-fields](parts/001.product-fields/README.md) | `ro.product.*` 机型字段、`ro.build.flavor/product/description` 里的机型代号 |
| [002.build-fingerprint](parts/002.build-fingerprint/README.md) | 指纹和 build 描述符,从原厂固件现取 |
| [003.version-label](parts/003.version-label/README.md) | `ro.build.display.id` 写版本号 |

三个部分合起来才是一致的"机型身份",所以合成一个补丁(2026-11-01)。相关但不是同一件事的,单独成补丁:

- [`debug-off`](../debug-off/README.md):去掉 Mystic 的调试段,关 ADB 免授权/调试,`build.prop` 权限改 0644。**发布的镜像不要去掉。**
- [`kernel-builder-string`](../../boot-kernel/kernel-builder-string/README.md):**改 boot**,内核里 `build-user@build-host` → `androidbld@abfarmhost`。

## 顺序和独立性

这三个部分和 `debug-off` 之间**互不依赖,任意顺序结果都一样**(下面是原因和实测)。`device.conf` 的 `MODS` 里写的是 `product-fields` → `build-fingerprint` → `debug-off` → `version-label`,只是习惯顺序。

两个模块会碰同样的两个属性(`ro.build.flavor`、`ro.build.description`),处理方式是让结果和顺序无关:

- `build-fingerprint` 总是写原厂值(`--add-missing`,key 不存在也补),谁先谁后它都能跑。
- `product-fields` 只在这两个属性**开头还是 GSI 原机代号**(`tangorpro-user`)时才换成 `TB321FU-user`;已经是原厂值就不碰。
- 所以:两个都开,不管顺序,结果都是原厂值;只开 `product-fields`,得到 `TB321FU-user 15 AP3A.241005.015 ...`(机型对了,版本串还是 GSI 的);只开 `build-fingerprint`,`ro.product.*` 还是 Pixel 的。
- `debug-off` 只删它自己认得的几个调试属性,不会误删别的模块追加在后面的行。

已实测:四个全开的三种顺序(正序、倒序、乱序),三份 build.prop 逐行相同;四个模块各自单开都跑通。

## 参数

都在 `devices/<设备>/conf.d/identity.conf`(机型字段、`GSI_CODENAME`、`DISPLAY_ID`),原厂固件镜像 `STOCK_SYSTEM_IMG` / `STOCK_VENDOR_IMG` 在 `device.conf`。

## 单独发布

本补丁可以带 `toolkit/` 单独发。`build-fingerprint` 需要用户自己提供原厂固件的 system 镜像,其它不依赖任何私有文件。
