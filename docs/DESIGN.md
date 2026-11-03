# DESIGN — 设计

[English](en/DESIGN.md) · [Español](es/DESIGN.md) · 简体中文

## 设计目标

- 联想拯救者 Y700 三代(TB321FU)上跑 Pixel GSI 的全部改动,**从原始材料一条命令重新构建**,取代"每版直接改上一版文件树"的手工流程。
- 一个小补丁一个文件夹,各自带身份文件、原理文档和应用脚本;互不依赖,依赖写明后构建时自动处理;想要哪个打哪个。
- 补丁与底包解耦:换 GSI 来源或安卓版本时,用 `make survey` 摸底,逐个评估补丁是否适用。

## 架构

构建 = 原始材料 + 依次 apply 选中的补丁 + 打包:GSI 底包经 system 补丁得 system 镜像 + vbmeta_system,原厂 boot 经固件补丁得 boot 集,再与原厂 9008 包合成保数据刷机包。

顶层目录及其职责:

| 目录 | 职责 |
|---|---|
| `patches/` | 所有补丁,一个文件夹一个补丁(含 `apply.sh`);大类文件夹只用于归类和批量选择 |
| `toolkit/` | 构建框架:`build.sh`、`build-9008.sh`、`select.sh`、`gen-index.sh`、`lib/`、`tests/`、`avb/`、`flash9008/` 等 |
| `devices/<设备>/` | `device.conf`(补丁目录、路径、签名)、`conf.d/*.conf`(各补丁参数)、`profiles/`(选择预设) |
| `docs/` | 项目文档;`topics/` 是几个旧组的背景说明 |

构建输出(`out/`)、私有件(`private/`)不进仓库。补丁写法见 [docs/MODULE-SPEC.md](MODULE-SPEC.md)。

## 设计约束

- 补丁顺序永远按 `device.conf` 的 `MODS`;构建前按各 `patch.conf` 的 `REQUIRES`/`AFTER`/`BEFORE` 核对。
- 选补丁不改 `device.conf`,用构建时的选择规则(`PROFILE`/`WITH`/`WITHOUT`),三步(system、boot、9008)用同一份选择。
- 删除类补丁遇到底包里本没有的东西只记日志、不算失败;前提不满足的补丁报错说明原因,不悄悄少打。

## 数据设计

构建输入来自平级的数据工程目录(`device.conf` 的 `OLD`,`TB321FU_DATA` 可覆盖):底包、原厂固件、工具、各版本成品(`releases/`)、`legacy/` 手工流程遗留。正式版成品按 `user-vX.Y` 命名并打 `KEEP` 保护(见 `toolkit/clean-releases.sh`)。

## 扩展

新增补丁 = 新建一个文件夹,放 `patch.conf`(身份、依赖、顺序、开关)、`README.md`(原理)、`apply.sh`(改动),规则见 [docs/MODULE-SPEC.md](MODULE-SPEC.md)。
