# 9008 保数据刷机包

TB321FU 平时用 9008(高通 EDL)刷机:原厂 9008 包里的 boot / vendor / 基带等一律不动,只把 super 里的 system_a 换成我们的 GSI,再换上 boot 集和 vbmeta_system,userdata / metadata / persist 原样保留,刷完不清数据。这篇讲包是怎么拼出来的、为什么这样拼、换东西时要重做什么。

工具在 `toolkit/flash9008/`(用法见它的 README),system 和 boot 集都由 `toolkit/build.sh` 一次生成(输出目录下的 `system/`、`firmware/`)(boot 补丁见 `patches/required/general/boot-kernel/boot-assemble/` 和它的贡献者,主 vbmeta 重签见 [AVB-RESIGN.md](AVB-RESIGN.md))。

## 1. 原厂 9008 包长什么样

`TB321FU_ZUI_17.0.12_OPEN_9008FACTORY_CRACKED.7z` 解开后 `image/` 下有:

- `xbl_s_devprg_ns.melf`:Firehose 编程器。`Qsaharaserver` 先把它送进 EDL 模式的设备
- `rawprogram0..5.xml`:UFS 的 LUN0..LUN5 各一份,每条 `<program>` 是"把哪个文件写到哪个扇区"
- `patch0..5.xml`:写完后修 GPT 用
- `rawprogram_save_persist_unsparse0.xml`:LUN0 的另一个版本,名字说保留 persist。**它会清 userdata 和 metadata**,不能直接用(见第 4 节)
- 各分区镜像:boot.img、vendor_boot.img、dtbo.img、vbmeta.img、vbmeta_system.img、super_1..8.img……

刷机命令(`flash_v49.bat` 和用户的 `flash_auto.ps1` 都是这个结构):

```
Qsaharaserver -p \\.\COMx -s 13:image\xbl_s_devprg_ns.melf
fh_loader --port=\\.\COMx --search_path=image
          --sendxml=<LUN0 的 XML>,rawprogram1.xml,…,rawprogram5.xml
          --sendxml=patch0.xml,…,patch5.xml
          --setactivepartition=1 --memoryname=ufs --zlpawarehost=1 --noprompt
fh_loader --port=\\.\COMx --reset --noprompt
```

UFS 扇区是 4096 字节。`fh_loader` 写一条 `<program>` 时,文件大小必须正好等于 `num_partition_sectors × 4096`;`filename=""` 的条目只声明分区,不写数据。

## 2. super 怎么分片

super 在 LUN0,从扇区 90504 开始,共 13958643712 字节。9008 包没有给一整块 super.img,而是按逻辑分区切成 8 片原始字节(不是 sparse 格式),每片一条 `<program>`:

| 文件 | LUN0 扇区 | super 内偏移 | 内容 |
|---|---|---|---|
| super_1.img | 90504 | 0 | lp 元数据,405504 字节 |
| super_2.img | 90760 | 1 MiB | odm_a |
| super_3.img | 91016 | 2 MiB | product_a |
| super_4.img | 600968 | 2090860544 | **system_a**(原厂 3702558720 字节) |
| super_5.img | 1505160 | … | system_dlkm_a |
| super_6.img | 1508232 | … | system_ext_a |
| super_7.img | 1605768 | … | vendor_a |
| super_8.img | 1973896 | … | vendor_dlkm_a |

分片之间的空隙和 `_b` 槽(都是空分区)不写。每一片在 super 里的位置 = (start_sector − 90504) × 4096,正好是 lp 元数据里那个分区 extent 的起点。所以换 system 只需要两件事:把 super_4 换成我们的镜像,把 lp 元数据里 system_a 的大小改成镜像的大小。

`toolkit/flash9008/simsuper.py` 按 XML 和 lp 元数据把分片"虚拟拼回"super,用来做结构检查,也能把 vendor.img 等逻辑分区切出来(`patches/` 里的补丁要读原厂 vendor 时用)。

## 3. lp 元数据

super_1 = super 开头 405504 字节:4096 字节保留区 + 2 份 geometry(各 4096)+ 3 个 slot 的主元数据 + 3 份备份(每份 65536 字节)。每份元数据里有分区表、extent 表、组表、块设备表,头部带 tables 和 header 两个 sha256。

`lp.py resize` 在 6 份里把 system_a 唯一的 extent 改成新大小,重算两个 sha256。只能缩小:super 里分区首尾相接,放大会压到后面的 system_dlkm_a,要放大得重排整个 super,这个工具不做。

**system_a 的大小必须正好等于 system 镜像的大小。**AVB 的 hashtree footer 在分区最后 64 字节。分区比镜像大,开机时 fs_mgr 去分区末尾找 footer 找不到,verity 起不来;锁 BL 后就是不开机。V57 踩过:erofs 重打包后镜像大小漂了 ±4096,签名脚本按镜像大小算 partition_size,footer 落在错误的位置。从那以后 system 镜像签名时分区大小固定为 `SYSTEM_PART_SIZE`(1882984448 = 459713 × 4096),super_1 和 XML 都按镜像实际大小生成,三者自然对齐。`SYSTEM_PART_SIZE` 不能超过原厂 system_a 的 3702558720。

## 4. 哪些分区必须 filename 为空

LUN0 XML 里这些条目必须 `filename=""`、也不能有 `<erase>`,否则刷机会把它们写成出厂内容:

| 分区 | 里面是什么 | 写了会怎样 |
|---|---|---|
| userdata | 用户数据 | 直接没了 |
| metadata | FBE 文件加密密钥的包装状态 | userdata 字节没动,但密钥对不上,开机进 recovery 要求清 data。V48 第一版只清了 userdata 的 filename、漏了 metadata,就是这样 |
| persist | 传感器校准、Wi-Fi/蓝牙 MAC、DRM 等出厂数据 | 校准丢失 |
| misc、keystore、frp | 启动命令、密钥存储、恢复出厂保护 | 原厂 XML 里本来就为空,保持 |
| proinfo、lenovolock、ssd 等 | 联想自己的分区(proinfo 一般放 SN 等出厂信息) | 同上,原厂就为空。基准里为空的条目工具都要求保持为空 |

另外 LUN 其它 XML 里的 `modemst1/2`、`fsg`、`fsc`(基带 EFS,IMEI 在里面)、`devinfo` 原厂就为空,工具也会检查。

原厂 `rawprogram_save_persist_unsparse0.xml` 只把 persist 设成空,userdata 的 10 条写的是 `userdata_N.img`、metadata 的 7 条写的是 `metadata_N.img`(都是格式化后的空文件系统)——刷了等于清数据。V48 照着 persist 的写法把 userdata 和 metadata 都改成空,V49 起一直用这一份。

**XML 一律以真机刷过、确认没清数据的那份为基准,只改两行。**V51 用了 `/tmp/9008_inspect/image/` 下同名的原厂文件当基准去替换 super 那两行,没和 V50 的做全文 diff,结果刷完数据被清。`mk_rawprogram.py` 现在会:拒绝不保数据的基准;只改 super_1 那行的 filename、system_a 那行的 filename 和扇区数;生成后和基准全文逐行比,多一处差异就失败;输出再查一遍保数据。TB321FU 的基准是 `tb321fu_pixelos_15_tangorpro_ap3a.241005.015/9008-V49-patch/rawprogram_save_persist_unsparse0_v49.xml`。

## 5. 版本专属文件和 boot 集

一个版本 N 要的文件(用户刷机目录 `image\` 下):

| 文件 | 来源 | 随什么变 |
|---|---|---|
| `super_1_vN.img` | 原厂 super_1 + `lp.py resize` | system 镜像大小(V57 起固定,实际每版都一样) |
| `super_4_vN.img` | system 镜像本身,改个名 | 每版 |
| `rawprogram_save_persist_unsparse0_vN.xml` | 基准 XML 改两行 | 每版(文件名) |
| `VN\vbmeta_system.img` | `toolkit/avb_resign.sh system`(调 `mk_vbmeta_system.py`)| 每版(system 的 hashtree 根摘要) |
| `VN\boot.img` | `boot-assemble` 等改 boot 的补丁(`toolkit/build.sh`) | 原厂固件 |
| `VN\vbmeta.img` | `toolkit/avb_resign.sh main` | 原厂固件,或 dtbo/init_boot/vendor_boot 变了 |
| `VN\init_boot.img`、`VN\vendor_boot.img` | 原厂原样 | 原厂固件 |

刷机前要把 `VN\*.img` 拷到 `image\` 下覆盖原厂同名文件(`flash_v49.bat` 里是 `copy /y image\V49\*.img image\`,flash_auto 按 `-Version N` 做同样的替换,细节以用户那边的脚本为准,本仓库里没有 flash_auto),rawprogram1..5 和 LUN0 XML 里引用的 boot.img、vbmeta.img、vbmeta_system.img 等就成了我们的。

AVB 链(第 6 节核对的就是它):主 vbmeta 用 chain 只钉 boot、vbmeta_system 的公钥,所以出新 system 只换 vbmeta_system,主 vbmeta 不动;dtbo / init_boot / vendor_boot 钉的是内容摘要,固件里这几个变了主 vbmeta 就得重签。详见 [AVB-RESIGN.md](AVB-RESIGN.md)。

## 6. 包的生成和检查

`toolkit/flash9008/make_9008_patch.sh` 按顺序做,任何一步不过就停:

1. super_1:lp 元数据里 system_a 改成镜像大小
2. LUN0 XML:基准改两行 + 全文 diff + 保数据检查(也查 rawprogram1..5)
3. super 布局:每个分片落在哪个逻辑分区、大小对不对、有没有重叠越界
4. AVB 链:主 vbmeta(flags 必须是 0)→ boot、vbmeta_system 的公钥 → dtbo/init_boot/vendor_boot/boot 的摘要 → system/system_ext/product/vendor/… 在 super 里的 footer。本机没有 recovery.img、pvmfw.img 时这两个记"未核对"
5. 打包:system 对基准版本出 xdelta 补丁,立刻还原比 sha256;写 manifest;bat/ps1 行尾检查;压 7z

为什么出 xdelta 补丁:刷机在用户另一台 Windows 电脑上,网慢,system 镜像 1.9GB。那边刷机目录里已经有 V49 的 `super_4_v49.img`,每版只传十几 MB 的补丁,在本地还原。

## 7. 用户那边的刷机目录标准(flash_select / flash_auto)

2026-10-30 起用户用这套,patch 包必须按它的结构出:

```
刷机目录\
  flash_select.bat / flash_select.ps1     选版本菜单,备注写在 flash_select.ps1 的 $notes 表
  flash_auto.ps1                          flash_auto.ps1 -Version N 全自动刷
  apply_patch.bat / apply_patch.ps1       patch 包带来的
  tool\  Qsaharaserver.exe fh_loader.exe xdelta3.exe
  image\ 原厂 9008 包的全部文件(rawprogram1..5、patch0..5、xbl_s_devprg_ns.melf、super_2..8.img…)
         super_1_vN.img  super_4_vN.img  rawprogram_save_persist_unsparse0_vN.xml
         VN\ boot.img init_boot.img vendor_boot.img vbmeta.img vbmeta_system.img
  patch\VN\ manifest.json  system_vB_to_vN.patch
```

flash_auto 刷之前自己也做保数据检查(受保护分区不得有 filename/erase)和 super 容量检查。

用户的操作:
1. patch 包 7z 解压到刷机目录根,同名覆盖
2. 双击 `apply_patch.bat`:读 `patch\VN\manifest.json`,核对包里文件的 sha256;用 `image\super_4_vB.img` + xdelta 还原出 `super_4_vN.img` 并比 sha256;`VN\` 里缺的 boot 集文件从别的 `Vxx\` 目录找 sha256 一致的复制过来
3. `flash_select.bat` 选 VN 刷入

每出一个版本,给用户一行 `$notes` 备注(`mk_patch_pkg.py` 最后会打印)。

`.bat` 必须 CRLF。V49 第一版 `flash_v49.bat` 是 LF 的,Windows 上容易被杀毒当可疑文件处理。已经是 CRLF 的文件别再 `sed 's/$/\r/'`,会变成 CR CR LF。`apply_patch.ps1` 还要带 UTF-8 BOM,Windows PowerShell 5 没 BOM 会按本地代码页读中文。

## 8. 换东西时要重做什么

| 换了什么 | 要重做 |
|---|---|
| 只换 system(出新版本) | `toolkit/build.sh` 出 system + vbmeta_system(和 boot 集)→ `make_9008_patch.sh`,或者一步 `make 9008`。boot 集不变,不进包 |
| system 镜像大小(`SYSTEM_PART_SIZE`) | 同上,super_1 和 XML 自动跟着变。新大小不能超过原厂 system_a |
| 原厂固件(新的 9008 包) | ① 解 `image/`,用 `simsuper.py` 切出 vendor 等逻辑分区,改 device.conf 的 `STOCK_*` 和 firmware.conf 的 `FLASH9008_STOCK_DIRS`;② 清掉 firmware.conf 里的 `*_EXPECT_SHA256`、`FW_BOOT_SALT`、`FW_BOOT_DROP_DUP_PROPS`,跑 `toolkit/build.sh` 重做 boot 和 vbmeta(**不能拿旧固件的补丁 boot 来配**,见 `patches/required/general/boot-kernel/boot-assemble/README.md`);③ 用新固件的 vbmeta_system 当 `STOCK_VBMETA_SYSTEM` 重出 system;④ 新包的 LUN0 XML 要重新做一份保数据基准:拿原厂 XML 把 userdata、metadata 的 filename 清空(和 V48 一样),**先人工 diff 确认只动了这些**,真机刷一次确认没清数据,再把它设成 `FLASH9008_BASE_XML`;⑤ 出包时 `FLASH9008_INCLUDE_BOOT_SET=1`;⑥ xdelta 的基准:用户刷机目录里没有和新固件配套的旧 system 时,`--base-image` 仍可以用 V49 的 super_4(只要用户那边有这个文件),补丁会大一些 |
| 增量基准(用户换掉了 super_4_v49.img) | 改 `FLASH9008_BASE_VERSION/IMAGE/SHA256` |
| 刷机目录标准 | 改 `win/apply_patch.ps1` 和 `mk_patch_pkg.py` 的包结构、manifest |

## 9. 踩过的坑

- **V6(10-27)**:路线 B 第一次把 GSI 打进 9008 包,确立了"换 super_4 + 改 lp 里 system_a 大小 + 新 XML"的做法。
- **V48(10-30)**:原厂 save_persist XML 会清 userdata,改成 filename 为空;第一版漏了 metadata,刷完要求清 data,补上 metadata。
- **V49**:`flash_v49.bat` 忘了 CRLF。
- **V51**:用错了 XML 基准(同名的原厂文件),清了用户数据。以后只以验证过的 XML 为基准、改完全文 diff。
- **V57**:system 镜像大小漂移,AVB footer 落错位置。分区大小固定。

## 10. 验证记录

2026-10-31,用 V66 的 system 镜像和 vbmeta_system、`toolkit/build-firmware.sh` 生成的 boot 集跑 `make_9008_patch.sh`:

- super_1_v66.img、rawprogram_save_persist_unsparse0_v66.xml 和 V66 发布用的两份逐字节一致
- 展开的整个包目录和发布的 `TB321FU_V66_9008patch.7z` 解出来的内容 `diff -r` 无差异(包括 xdelta 补丁和 manifest)
- AVB 链核对通过(recovery、pvmfw 本机没有镜像,未核对)
- boot.img 和真机在用的 `276324c4…` 一致,vbmeta.img 和 `c30043ec…` 一致
