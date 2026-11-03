# popup-fix — 开机弹窗修复

GSI 的 framework 和联想 vendor 不是同一套编译产物,所以开机会弹「设备内部出现了问题」。这一组去掉这个弹窗。

| 模块 | 做什么 | 能不能单独关 | 运行时开关 |
|---|---|---|---|
| [`build-consistency-dialog`](../../patches/required/general/bug-fix/build-consistency-dialog-fix/README.md) | 改 framework.jar:`Build.isBuildConsistent()` 直接 return true,去掉开机弹窗 | 能,从 `MODS` 删一行 | 无 |

改了 `framework.jar` 之后系统里预编译的 boot image 会过期,清理由 [stale-boot-image](art-cache.md) 负责;两个模块互不依赖(`stale-boot-image` 靠 `mark_modified`/`was_modified` 的改动标记工作)。

## 整组独立发布时要带什么

`patches/required/general/bug-fix/build-consistency-dialog-fix/` + `toolkit/`(`jarpatch.py`、`common.sh` 的 `mark_modified`)。除 `APKTOOL_JAR` 外无额外参数。

## 版本

在 V66 底包上验证:framework.jar 的 5 份 dex 与 V66 逐字节相同(只有 classes3.dex 是补丁版)。V47 加弹窗补丁,历史见模块 README。
