# boot-assemble — 汇总改动、重签 boot

## 做什么

读原厂 `boot.img`,把 boot 贡献者登记的所有改动(cmdline 参数、内核字节替换)**一次性**应用,再按原来的签名参数重签,输出 `$FW_OUT/boot.img`。必须排在所有 boot 贡献者后面。

## 登记格式

贡献者用 `common.sh` 的 `contrib_add_text boot <名字> <内容> <类型>` 往产物 `boot` 登记。类型存在 `.marker` 里,assemble 靠它区分:

| 类型 | 文件内容 | assemble 怎么用 |
|---|---|---|
| `cmdline` | 一行,空格分隔的内核命令行参数,例如 `enforcing=1 selinux=1` | 所有 `cmdline` 登记合并,追加到 boot header 的 cmdline 后面,对应 `patch_boot.py --cmdline` |
| `replace` | 两行:第一行 FROM,第二行 TO,两者字节数必须相同 | 在内核区域里把 FROM 等长替换成 TO,对应 `patch_boot.py --replace FROM TO` |

不认识的类型 assemble 会直接失败。以后要加新的改动种类(比如改 ramdisk),在这里加一种类型、在 `patch_boot.py` 里加对应处理。

两个现有贡献者:[selinux/kernel-enforcing](../../../tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/fix/parts/002.kernel-enforcing/README.md)(登记 `cmdline`)、[kernel-builder-string](../kernel-builder-string/README.md)(登记 `replace`)。

### 只启用一部分时

| 启用的贡献者 | 结果 |
|---|---|
| 两个都启用 | cmdline 有 `enforcing=1 selinux=1`,内核字符串换掉(V48/V49 在用的那颗) |
| 只有 `kernel-enforcing` | 只改 cmdline,内核字符串不动 |
| 只有 `kernel-builder-string` | 只换内核字符串,cmdline 保持原厂的空 |
| 一个都没有 | assemble 干净跳过,boot 保持原厂(原样拷到 `$FW_OUT/boot.img`),后面的 vbmeta 照常处理 |
| 有贡献者但没有 assemble | 收尾 `check_contribs` 报错,构建失败 |

另外 `patch_boot.py` 会拒绝:几个 `--cmdline` 里出现同名参数(两个模块在设同一个参数)、两条 `--replace` 在内核里命中位置重叠、替换前后长度不同。

## 原理

### 重签

boot 是主 vbmeta 用 chain descriptor 链过来的:主 vbmeta 只钉了 boot 的签名公钥(testkey_rsa4096,sha1 `2597c218`),不钉 boot 的内容摘要。所以 boot 只要用同一把 key 重签,主 vbmeta 一个字节都不用改。

重签时从原 boot 的 AVB footer 现读所有参数:算法 `SHA256_RSA4096`、rollback_index `1746403200`、rollback_index_location 0、flags 0、release string、分区大小 100663296、hash descriptor 的 salt 和 image_size、以及全部 property descriptor(os_version、fingerprint、security_patch)。hash descriptor 的摘要按新内容重算,其余 descriptor 原样保留。salt 默认沿用原 boot 的,同样的输入每次出同样的结果。

`patch_boot.py` 的步骤(每步不满足前提就失败退出,不出半成品):

1. 读原 boot 的 AVB footer 和 vbmeta,要求:签名有效、只有一个 hash descriptor 且名字是 boot、摘要和镜像内容对得上(说明是没动过的原厂镜像)、签名公钥等于 `--key` 的公钥。
2. 按 boot header 版本解析。只认 v3/v4:cmdline 在 header 的 offset 44,固定 1536 字节,NUL 结尾;页大小固定 4096,内核从 4096 开始。v0–v2 的位置不一样(offset 64 开始 512 字节,另有 1024 字节 extra_cmdline),脚本不猜,遇到就失败。
3. 应用 cmdline:原 cmdline 里已经有同名参数就失败,不覆盖别人的设置。
4. 应用字节替换:只在内核区域 `[4096, 4096 + kernel_size)` 里找,每条规则命中 0 处就失败。所有命中先在原始内核上找好再统一替换。
5. 重签。
6. 自检:avbtool 能验过签名、公钥没变、header 参数没变、footer 之前只有预期的那几处字节变了。

### 换固件必须重打,不能复用旧的补丁 boot

boot 里装的是 GKI 内核本体。vendor_boot / vendor_dlkm 里的内核模块是对着这颗内核的 KMI 和 vermagic(这一版是 `6.1.112-android14-11-gd03cb1d7abcd-ab12592111`)编的。拿别的固件的 boot 来配,模块可能加载不上,轻则缺硬件,重则不开机。AVB 签名公钥一样只说明"谁签的",不说明"内核和 vendor 配不配"。

所以规则是:**补丁 boot 永远从当前这套原厂固件的 boot.img 现打**。同一套固件下它和 system 版本无关,可以一直复用。本仓库不内置任何一版做好的 boot,也是这个原因。

## 改动清单

只改 boot.img。两个贡献者都启用时,footer 之前的区域一共变 69 字节:

- header offset 44 起的 cmdline:`""` → `"enforcing=1 selinux=1"`(21 字节)
- 内核里 3 处编译者字符串,每处 21 字节里有 16 字节不同
- AVB footer 和 vbmeta:重签

## 输入

| 来源 | 说明 |
|---|---|
| `FW_BOOT_STOCK` | 原厂 boot.img(必须是没动过的,脚本会核对摘要) |
| `AVB_KEY_VBMETA` | 签名私钥。公钥必须和原 boot 的签名公钥一样,不一样就失败 |
| `AVBTOOL` | avbtool.py 路径 |
| `FW_OUT` | `toolkit/build.sh` 给的固件目录,写出 `$FW_OUT/boot.img` |
| `FW_BOOT_SALT` | 可选。hash descriptor 的 salt(hex),不给就沿用原 boot 的 |
| `FW_BOOT_DROP_DUP_PROPS=1` | 可选。去掉完全重复的 property descriptor |
| `FW_BOOT_EXPECT_SHA256` | 可选。由 `toolkit/build.sh` 在最后核对结果的 sha256 |
| 贡献者登记 | `FW_BOOT_CMDLINE`、`FW_BOOT_KBUILD_FROM/TO` 由各贡献者读,assemble 不直接读 |

TB321FU A15 的 firmware.conf 给了 `FW_BOOT_SALT` 和 `FW_BOOT_DROP_DUP_PROPS=1`,只是为了让结果和真机在用的那颗 boot(`276324c4…`)逐字节一样。V47 那次重签用了 avbtool 的随机 salt,并且原厂 footer 里 `com.android.build.boot.security_patch` 有两条一模一样的,V47 只留了一条。这两处差别都无害(salt 只要和摘要配套,ABL 不关心它是多少;重复的属性 descriptor 只是信息)。保持逐字节一样的好处是用户刷机目录里已有的 boot.img 还能按 sha256 被 apply_patch 认出来。**换了原厂 boot 就把这两项和 `FW_BOOT_EXPECT_SHA256` 清空。**

注意这两项只在"两个贡献者都启用"时对得上 `276324c4…`;只启用一个贡献者时 sha256 当然不同,此时用 `ONLY=` 跑(不核对 expect),或者清空 `FW_BOOT_EXPECT_SHA256`。

## 依赖和顺序

排在所有 boot 贡献者(`selinux/fix`、`kernel-builder-string`…)后面。主 vbmeta 的重签不是补丁,`toolkit/build.sh` 在全部补丁之后自动调 `toolkit/avb_resign.sh main`。

## 适用范围和换底包注意

依赖原厂固件的 `boot.img`(TB321FU 上是 9008 包 `image/boot.img`,`base-fw-a15/boot.img` 是同一份,sha `c65d8313…`)。换固件后按顺序会在这些地方失败,失败了就是规则需要人看:

1. 原 boot 不是"一个 boot hash descriptor + 若干属性",或摘要和内容对不上(拿到的是改过的 boot)
2. 签名公钥不是 `AVB_KEY_VBMETA` 那把
3. header 版本不是 v3/v4,或 header_size 不是 1580/1584
4. 原 cmdline 里已经有 `enforcing=` / `selinux=`(已经打过,或者厂商自己设了)
5. 内核里找不到要替换的字符串(压缩内核、或编译者变了)
6. 自检:签名、公钥、header 参数、footer 之前除了预期的字节之外有别的变化

换了固件之后,这颗新 boot 的摘要变了,但主 vbmeta 只钉公钥,不用因为 boot 重签主 vbmeta(除非 vendor_boot 等别的 hash 分区也变了,见 [docs/AVB-RESIGN.md](../../../../../docs/AVB-RESIGN.md))。

## 踩过的坑

- **V47**:想直接复用 V7.5 的补丁 boot,但它是对着 A16 时期的原厂底(vendor_boot sha `0331304b…`)打的,和 A15 这条线的 vendor_boot(`e1d67f87…`)不是一代固件,KMI 对不上。被用户当场指出,作废后对着 A15 原厂 boot 重打。
- **V47**:重签用 avbtool 随机 salt,并去掉了一条重复属性,所以才有 `FW_BOOT_SALT` / `FW_BOOT_DROP_DUP_PROPS` 这两个为了逐字节对照而存在的选项。

## 验证

本机(2026-10-31):

- 两个贡献者都启用,`base-fw-a15/boot.img` 按 firmware.conf 的参数生成,结果 sha256 `276324c4a27e2028b719c26d0f1fcb208ac1c8b887293b0cfdabf22857ae22ec`,和 V48-PIF / V49-PIF 的 boot.img **逐字节一致**。
- 不给 `FW_BOOT_SALT` / `FW_BOOT_DROP_DUP_PROPS`(换固件后的默认用法),footer 之前的 35311616 字节和 V48 一致,只有 vbmeta 区不同(salt、摘要、签名、多一条属性)。
- 只启用 kernel-enforcing:cmdline 是 `enforcing=1 selinux=1`,内核里 `build-user@build-host` 仍是 3 处。只启用 kernel-builder-string:cmdline 为空,内核里 3 处都换成了 `androidbld@abfarmhost`。

刷机后的检查见两个贡献者的 README。
