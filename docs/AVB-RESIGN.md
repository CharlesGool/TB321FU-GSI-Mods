# AVB 重签(avb_resign)— 打完补丁后的收尾步骤

## 它是什么、为什么不是模块

没有哪个分区的内容是"改在 vbmeta 里"的:vbmeta 只是别的分区变了之后要跟着重算、重签的那一层。所以它不是 `patches/` 下的补丁,而是 `toolkit/avb_resign.sh`,由两个 make 脚本在**打完所有补丁之后**调用:

| 子命令 | 谁调用 | 做什么 | 输出 |
|---|---|---|---|
| `avb_resign.sh main <device.conf> <固件输出目录>` | `toolkit/build.sh`(全部补丁之后) | 按实际要刷的分区文件重算主 vbmeta 的 hash 摘要,flags=0 重签 | `vbmeta.img` |
| `avb_resign.sh system <device.conf> <system.img> <输出目录>` | `toolkit/build.sh`(erofs 打好之后) | 给 system 加 hashtree 签名,再生成配套的 vbmeta_system(沿用原厂其它 descriptor,只换 system 的 hashtree) | 签好的 system.img、`vbmeta_system.img` |

没有顺序问题要排:它在所有模块之后跑。有 `ONLY=` 的调试构建会跳过它(出来的东西本来就不能刷)。

## 做什么(main)

按实际要刷进去的分区文件,重算主 vbmeta 里各 hash descriptor 的摘要,用原厂同一把 key 重签,flags 保持 0。解决的是"CRACKED 固件改了 vendor_boot 却没重签 vbmeta,结果锁不了 BL"。

## 原理

### 主 vbmeta 钉了什么

TB321FU OPEN 版的 AVB 信任根就是 AOSP testkey(不是联想私钥),ABL 只信 testkey_rsa4096。签名链:

```
ABL 内置 testkey_rsa4096 公钥
 └─ vbmeta(testkey_rsa4096,flags=0)
     ├─ chain boot / recovery          只钉公钥 2597c218(testkey_rsa4096)
     ├─ chain vbmeta_system            只钉公钥 cdbb7717(testkey_rsa2048)
     │    └─ vbmeta_system:system / system_ext / product 的 hashtree + pvmfw 的 hash
     ├─ hash dtbo / init_boot / vendor_boot      钉 sha256(salt ‖ 镜像前 image_size 字节)
     └─ hashtree odm / system_dlkm / vendor / vendor_dlkm   钉 dm-verity 根摘要
```

chain 分区只钉公钥,所以 boot、vbmeta_system 换内容只要同一把 key 重签就行,主 vbmeta 不用动。hash 分区钉的是内容摘要,dtbo / init_boot / vendor_boot 任何一个字节变了,主 vbmeta 就得跟着改。

### CRACKED 固件的问题(这个模块的由来)

`TB321FU_ZUI_17.0.12_OPEN_9008FACTORY_CRACKED.7z` 改了地区锁,改的是 vendor_boot 的 vendor ramdisk,但没重签 vbmeta:它的 vbmeta.img 和非 CRACKED 原版逐字节相同(sha `bf0fa2aa…`),仍钉着原版 vendor_boot 的摘要 `1d4ac81b…`,实际刷进去的 vendor_boot(文件 sha `e1d67f87…`)算出来是 `91ba6e63…`。

解锁状态下 ABL 不拦校验错误,所以能开机;`fastboot flashing lock` 之后校验 vendor_boot 失败,锁不上(用户 2026-10-29 实测)。对照 17.5.10.170 的 CRACKED V2 包:`changeRegion/` 目录也是同样的病,`changeRegion_Resign/` 把摘要改对了才能锁。

修法就是把 vendor_boot 的摘要改成实际值、重签。脚本把这件事做成通用的:对每个 hash descriptor 都按给的文件重算,没变的保持原样,变了的只改摘要(和 image_size)。

### 为什么主 vbmeta 不因为 boot 改而变

boot 是 chain descriptor,只钉公钥。`boot-assemble` 用同一把 key 重签 boot,主 vbmeta 里 boot 那条一个字节都不用改。本模块对 boot 只做核对:签名公钥等于 chain 里钉的那把、boot 自己的 vbmeta 签名有效。这也是它必须在 boot 补丁生成之后才跑的原因。

### 为什么 flags 必须是 0

flags=0 是开启校验。flags=2(`AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED`)的主 vbmeta 在这台机器上会被 ABL 拒,而且解锁状态下也会马上把槽位标成不可启动(V6 期间刷机那边二分定位过)。所以脚本沿用原厂 flags,原厂不是 0 就直接失败。

### vbmeta_system(`avb_resign.sh system`)

vbmeta_system 跟着 system 镜像走,每个 system 版本都要重出,由 `avb_resign.sh system` 调 `toolkit/avb/mk_vbmeta_system.py` 生成:原厂 vbmeta_system 的其它 descriptor 原样保留,只把 system 的 hashtree descriptor 换成新 system 镜像 footer 里那份,testkey_rsa2048 重签,rollback_index/flags 沿用原厂。主 vbmeta 对 vbmeta_system 只钉公钥,所以出新 system 时主 vbmeta 不用动。

## 脚本怎么处理每种 descriptor

| 类型 | 处理 |
|---|---|
| hash | 必须给 `--image 名=文件`。文件带 AVB footer 时 image_size 取 footer 的 original_image_size,salt 沿用 vbmeta 里的。摘要不同就改 |
| hashtree | 必须给 `--image`(或显式 `--skip`)。读文件自己 footer 里同名的 hashtree descriptor,和 vbmeta 里的逐字节比,**不一样就失败**——这说明 super 里的逻辑分区被改过,要换整个 descriptor,这个脚本不替你决定 |
| chain | 给了 `--image` 就核对该镜像的签名公钥等于钉的公钥,不给只提示 |
| property | 原样保留 |
| 其它 | 失败 |

签名参数全部沿用原 vbmeta(算法、rollback_index、rollback_index_location、flags、release string);重签的 key 公钥必须和原 vbmeta 的一样(ABL 只认烧在机器里的那把,换 key 必砖)。输出补零到原文件大小(8192)。最后自检:签名有效、header 参数没变、只有预期的 descriptor 变了。

只核对 hashtree descriptor 和分区自己 footer 里的是否一致,不重算整棵 dm-verity 树(vendor 有 1.5GB,而且原厂分区没动过,两边一致就够了)。

## 改动清单

`main` 只生成 `<固件输出目录>/vbmeta.img`。TB321FU A15:只有 vendor_boot 的摘要 `1d4ac81b…` → `91ba6e63…`,加上 auth 块(hash + RSA 签名)重算。

## 输入

| 变量 | 说明 |
|---|---|
| `FW_VBMETA_STOCK` | 原厂主 vbmeta |
| `AVB_KEY_VBMETA` | testkey_rsa4096,公钥必须和原 vbmeta 的一样 |
| `FW_VBMETA_IMAGES`(数组) | 每个 descriptor 对应的分区文件,`名字=文件`。boot 不用写,脚本自动用 `<固件输出目录>/boot.img`(没启用任何 boot 补丁时用 `FW_BOOT_STOCK`)。super 里的逻辑分区(odm/vendor…)用 `toolkit/flash9008/simsuper.py` 从 9008 包切出来。脚本直接 source `$CONF`,数组变量可用 |
| `FW_VBMETA_EXPECT_SHA256` | 可选,由 `toolkit/build.sh` 核对结果 sha256 |
| `AVBTOOL` | avbtool 路径 |
| `SYSTEM_PART_SIZE`、`AVB_KEY_SYSTEM`、`STOCK_VBMETA_SYSTEM`、`AVB_KEY_VBMETA_SYSTEM` | `system` 子命令用:分区大小(固定,按镜像大小算会漂 ±4096)、签名 key、原厂 vbmeta_system |

## 顺序

在所有模块之后跑,不需要在 `MODS` 里排。

## 适用范围和换底包注意

依赖原厂固件的 vbmeta.img、dtbo.img、init_boot.img、vendor_boot.img,和 super 里的 odm / system_dlkm / vendor / vendor_dlkm。换固件后:

- 新固件自己就是自洽的(没被人改过):脚本跑完所有 hash 都"一致",输出和原厂 vbmeta 逐字节相同,用原厂的也行。
- 改过 hash 分区(像 CRACKED 改 vendor_boot):脚本会重算并打出来是哪个分区变了。先确认这个改动是你认可的。
- 改过 super 里的逻辑分区:hashtree 核对失败。要么用没改过的分区,要么另写规则换 descriptor。
- 补丁 boot 不影响主 vbmeta(chain 只钉公钥),但脚本会核对补丁 boot 的签名公钥。

## 踩过的坑

- **V6 期间**:flags=2、不带 descriptor 的 vbmeta 被 ABL 拒,解锁状态下也立刻 slot-unbootable。
- **2026-10-29**:CRACKED 17.0.12 整刷后锁不了 BL,查出 vendor_boot 摘要没重签。当时手工改 aux 块里的 32 字节摘要再重签,出了 `base-fw-a15/vbmeta_resigned.img`(sha `c30043ec…`)。V48 起 9008 包的 vbmeta 都是它。
- 签名链里的 cdbb77 一度被误认成联想原厂 key,其实是 AOSP 公开的 testkey_rsa2048。

## 验证

本机(2026-10-31):`base-fw-a15/vbmeta_resigned.img` 和 V49/vbmeta.img 是同一个文件(sha256 都是 `c30043ec…`)。`toolkit/build.sh devices/tb321fu-a15/device.conf <out>`(内部调 `avb_resign.sh main`) 用 `base-fw-a15/vbmeta.img` + 原厂 dtbo/init_boot/vendor_boot + 切出来的 4 个逻辑分区,输出 sha256 `c30043ec2bdb8db2edabda052ca2d2d2fbfb237230295a1248b2921914f366f3`,**逐字节一致**。

刷机后锁 BL 前:`fastboot getvar unlocked` 确认状态,刷入后 `fastboot flashing lock`;锁后应是 `ro.boot.verifiedbootstate=green`、`ro.boot.vbmeta.device_state=locked`。设备里这两个属性可能被伪装,以 `fastboot getvar unlocked` 为准。

## 整体独立发布

可以:`toolkit/avb_resign.sh` + `toolkit/avb/`。原厂 vbmeta、各分区文件和 testkey 私钥由使用者提供。
