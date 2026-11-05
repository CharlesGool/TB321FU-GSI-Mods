# THIRD_PARTY_NOTICES — 第三方声明

[English](en/THIRD_PARTY_NOTICES.md) · [Español](es/THIRD_PARTY_NOTICES.md) · 简体中文

本仓库分发的第三方材料及其署名、许可与合规义务。本仓库自身代码(补丁、`toolkit/`、文档)以 GPL-3.0-or-later 发布。

## 第三方声明

### 组件清单

| 组件 | 版本/哈希 | 上游 | 许可证 | 使用方式 | 版权归属 | 合规义务 | 核验日期 |
|---|---|---|---|---|---|---|---|
| avbtool | AOSP | android.googlesource.com(platform/external/avb) | MIT | `toolkit/avb/avbtool.py`,随仓库分发,被 AVB 签名脚本调用 | The Android Open Source Project | 保留版权与许可声明(在文件头) | 2026-11-04 |
| herald-core | 见该仓库 | github.com/CharlesGool/herald-core | GPL-3.0-or-later 等(见该仓库) | `patches/required/general/herald-core` 是其 `patch/` 的同步副本(本作者作品,非外部第三方) | CharlesGool | 与 herald-core 一致 | 2026-11-04 |
| tb321fu-tango-patch | 见该仓库 | github.com/CharlesGool/tb321fu-tango-patch | GPL-3.0-or-later 等(见该仓库) | `patches/required/general/tango` 是其 `patch/` 的同步副本(本作者作品,非外部第三方;Tango 本体、`tango32.ko` 和小米 32 位库不在其中) | CharlesGool | 与 tb321fu-tango-patch 一致 | 2026-11-05 |

### 许可证文本

- 本仓库自身:GPL-3.0-or-later,全文见 `LICENSE`。
- avbtool:MIT,完整版权与许可原文在 `toolkit/avb/avbtool.py` 文件头。

### 源代码提供

本仓库分发的是补丁源码、构建脚本和文档,全部为源码形式,无额外源码提供义务。构建产物(system 镜像、9008 包)不在本仓库内。

### 合规审查

- Copyleft 组件:本仓库自身 GPL-3.0-or-later。`avbtool.py`(MIT)与 GPL-3.0 兼容。
- **不随本仓库分发的专有件**:人脸解锁所需的旷视 Megvii SDK、Pixel 设置的人脸教育页素材(`face_education_lottie.json`、`face_settings.mp4`)均为专有材料,已 gitignore,需使用者自备(见 各 `patches/required/tangorpro/<底包>/faceunlock` 的 README)。外部构建工具(Android NDK、apktool、dex2jar、xdelta3 等)不在仓库内,由使用者自备。
