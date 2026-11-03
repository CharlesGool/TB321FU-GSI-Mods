# flash9008 — 高通 9008(EDL)保数据刷机包工具

输入"原厂 9008 包解出来的 image/ 目录 + 新 system 镜像 + vbmeta_system + boot 集",输出一个 patch 包:用户解压到刷机目录根,双击 `apply_patch.bat` 在本地还原出完整文件,再用 `flash_select.bat` 刷入,不清 data。原理和完整流程见 `docs/FLASH-9008.md`。

不依赖具体机型:分区位置、扇区大小、super 布局都从 XML 和 lp 元数据现读。和机型有关的只有两处约定:受保护分区名单(`mk_rawprogram.py` 的 `PROTECTED`)和刷机目录的 `VN` 目录名(`win/apply_patch.ps1` 和用户的 flash_auto 都按这个找)。

## 文件

| 文件 | 作用 |
|---|---|
| `make_9008_patch.sh` | 增量补丁总入口(用户手里要有上一版),按顺序调下面这些,任何一步失败就停 |
| `make_9008_full.sh` | **完整刷机包**总入口(公开发布用):原厂 9008 包整套 + 新 system / vbmeta_system / boot 集,出清数据版 `flash.bat` 和保数据版 `flash_keep_data.bat`;检查步骤和上面一样。`toolkit/build-9008.sh --full` 和根目录的 `make-9008.sh` 都走这个 |
| `lp.py` | 读/改 super 开头的 lp 元数据。`resize` 改一个逻辑分区的大小(只能缩小),重算校验和 |
| `superview.py` | 按 XML 把 super 分片"虚拟拼回去",按 lp 元数据读逻辑分区,不落盘整块 super |
| `simsuper.py` | 结构检查(`--check`),或从 9008 包切出逻辑分区(vendor.img 等,给 mods 和 firmware 用) |
| `mk_rawprogram.py` | 以已验证保数据的 XML 为基准,只改 super_1 / system_a 两行,自动 diff 和保数据检查 |
| `check_avb.py` | 按刷完后的样子从主 vbmeta 往下核对整条 AVB 链 |
| `mk_patch_pkg.py` | xdelta 补丁 + 还原自检 + manifest + 7z |
| `win/apply_patch.bat`、`win/apply_patch.ps1` | 用户那边跑的脚本,原样抄自旧工程 `tools/std_patch/`(bat CRLF;ps1 CRLF + UTF-8 BOM) |

## 用法

```bash
# 有 device.conf 时(参数从 conf.d/firmware.conf 的 FLASH9008_* 取)
# --system-out 是 toolkit/build.sh 输出目录下的 system/,--boot-set 是它下面的 firmware/目录
toolkit/flash9008/make_9008_patch.sh --conf devices/tb321fu-a15/device.conf \
    --system-out /tmp/v67-out --boot-set /tmp/fw-out \
    --note "这一版改了什么" --out /tmp/pkg67

# 不用 conf,全写出来
toolkit/flash9008/make_9008_patch.sh \
    --stock-dir /path/9008/image --base-xml rawprogram_save_persist_unsparse0_v49.xml \
    --system system.img --vbmeta-system vbmeta_system.img --boot-set fw-out/ \
    --version 67 --base-version 49 --base-image super_4_v49.img --base-sha256 742f6711… \
    --xdelta-exe xdelta3.exe --device TB321FU --note "…" --out /tmp/pkg67
```

`--help` 列出全部参数。产物:`<out>/<DEVICE>_V<N>_9008patch.7z`(+ `.sha256`),展开的包内容在 `<out>/9008_v<N>_std/`,生成的 super_1 和 XML 在 `<out>/work_v<N>/image/`。

## 每一步检查什么

1. **super_1**:原厂 super_1.img 先校验 6 份元数据的 sha256 和内容一致,再把每份里 system_a 的 extent 改成 system 镜像字节数(必须 4096 对齐、不大于原 extent),重算校验和。
2. **XML**:
   - 基准本身必须保数据:`userdata` `metadata` `persist` 必须有条目且 `filename=""`;`misc` `keystore` `frp` `proinfo` `modemst1/2` `fsg` `fsc` `devinfo` 出现了就必须 `filename=""`;都不能有 `<erase>`。不满足就拒绝拿它当基准(V51 用错基准清过数据)。
   - 只改两行:super 第一条(lp 元数据)的 filename;system_a 那条的 filename 和 num_partition_sectors。system_a 那条按新 lp 元数据里 system_a 的起点定位,不按文件名猜。
   - 输出和基准逐行比,只有这两行不同、这两行里只有这几个属性不同,打印全文 diff;输出再做一遍保数据检查;原厂的 rawprogram1..5.xml 也做保数据检查(只查不改)。
3. **super 布局**:按新 XML 把分片放到 super 里,检查每个分片大小 = XML 扇区数 × 扇区大小、分片不重叠、每个分片正好落在一个逻辑分区里不越界、lp 里的分区互不重叠。
4. **AVB 链**:主 vbmeta 签名有效且 flags=0;chain 的 boot、vbmeta_system 签名公钥等于钉的公钥;hash 分区(dtbo、init_boot、vendor_boot、boot)摘要对得上;hashtree 分区(system、system_ext、product、vendor…)读 super 里该分区末尾的 AVB footer,descriptor 和 vbmeta 里的逐字节一致。找不到镜像的(TB321FU 本机一般是 recovery、pvmfw)记"未核对",`check_avb.py --strict` 时算失败。
5. **打包**:`win/` 下 bat 必须纯 CRLF、ps1 必须 CRLF + BOM;xdelta3 -e 后立刻 -d 还原比 sha256;manifest 里每个文件回算 sha256。

## manifest.json

`apply_patch.ps1` 读它,格式不能改:

```json
{
  "version": 66, "base": 49, "note": "…",
  "base_sha256": "<super_4_vB.img>", "super_4_sha256": "<还原结果>", "patch": "system_v49_to_v66.patch",
  "files": { "image/super_1_v66.img": "…", "image/rawprogram_save_persist_unsparse0_v66.xml": "…", "image/V66/vbmeta_system.img": "…" },
  "boot_set": { "boot.img": "…", "init_boot.img": "…", "vendor_boot.img": "…", "vbmeta.img": "…" }
}
```

`--include-boot-set` 时 boot 集四个文件也进包(`image/VN/`)并列进 `files`。

## 不在仓库里的东西

- Windows 版 `xdelta3.exe`(第三方二进制):用 `--xdelta-exe` 指定。TB321FU 用的在旧工程 `tb321fu_pixelos_15_tangorpro_ap3a.241005.015/inputs/tools/xdelta3.exe`。
- 原厂 9008 包:自己解压 `image/`。
- 本机要有 `xdelta3`、`7z`、python3(≥3.9)。

## 验证

2026-10-31 用 V66 的 system 镜像和 vbmeta_system 跑了一遍总入口:

- 生成的 super_1_v66.img、rawprogram_save_persist_unsparse0_v66.xml 和 V66 实际发布用的两份(`/tmp/v66_build/in/`)逐字节一致。
- 展开后的整个包目录(apply_patch.bat/ps1、tool/xdelta3.exe、image/、patch/V66/manifest.json 和 xdelta 补丁、补丁说明.md)和发布的 `TB321FU_V66_9008patch.7z` 解出来的 `diff -r` 无差异。7z 文件本身因为时间戳不同 sha256 不一样。
- 拿原厂那份会清数据的 `rawprogram_save_persist_unsparse0.xml` 当基准,第 2 步按预期拒绝。
