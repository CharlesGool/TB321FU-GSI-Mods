# gsi-hide/partition-verified

## 做什么

把 `partition.{system,vendor,odm,product,system_ext}.verified` 改成 1,和原厂一致。

## 原理

检测器看这几个属性判断分区有没有 dm-verity 保护。GSI 下 product/system_ext 是 system 里的目录,没有独立的 verity 挂载,读出来是 0。

- `product`、`system_ext` 两个:写进 `system/build.prop` 就生效。
- `system`、`vendor`、`odm` 三个:init 挂分区时就被设成 0,早于 build.prop 加载,build.prop 盖不住 → 再用 `init.hardenpartverified.rc` 在 `post-fs-data` 里 `setprop` 覆盖一次。

attestation 用的是 bootloader 传来的 vbmeta 摘要,和这些属性无关,不受影响。

## 改动清单

- `system/build.prop` 末尾追加 5 行 `partition.*.verified=1`。
- 加 `etc/init/init.hardenpartverified.rc`。

## 输入 / 依赖

无。

## 换底包注意

build.prop 是追加,不检查已有同名 key(别的 GSI 若已经写了 1,重复无害)。

## 验证

```bash
adb shell getprop | grep partition.*verified   # 五个都是 1
```
