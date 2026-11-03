# art-cache — 过期预编译产物清理

一旦改了 `framework.jar` 或 `services.jar`,系统里预编译的 boot image 和 system_server 的 services oat 就和 jar 对不上了。不清的话 ART 每次开机退回 memfd 编译,Hunter 等检测会报警。这一组负责清掉它们,让 ART 走正常的"开机编译一次、缓存到 /data"路径。

| 模块 | 做什么 | 能不能单独关 | 运行时开关 |
|---|---|---|---|
| [`stale-boot-image`](../../patches/required/general/boot-kernel/stale-boot-image/README.md) | 按"改动标记"删过期的预编译 boot image 和 services oat | 能 | 无 |

## 顺序和依赖

- 两个模块**不 `require_mod`** 对方。`stale-boot-image` 靠改动标记工作:改 jar 的模块(这一组的 `build-consistency-dialog`、`faceunlock` 组的 `services-hooks`)在换完 jar 后 `mark_modified`,`stale-boot-image` 用 `was_modified` 读。
- **`stale-boot-image` 必须排在所有改 jar 的模块后面**。排前面读不到标记,什么都不删;而改 jar 的模块发现它已经跑过会直接报错。`MODS` 里现在的排法:`faceunlock/services-hooks`、`faceunlock/app`、`faceunlock/settings-entry`、`build-consistency-dialog-fix`、`stale-boot-image`。
- 以后新增改 `framework.jar` / `services.jar` 的模块:换完 jar 调 `mark_modified framework/framework.jar`(或 `services.jar`),并排在 `stale-boot-image` 前面。

## 单独启用一个会怎样

| 启用 | 结果 |
|---|---|
| 只 `build-consistency-dialog` | 弹窗没了;但 boot image 和 services oat 没人清,留着对不上的预编译产物,ART 开机走 memfd 编译(Hunter 报警,功能不受影响) |
| 只 `stale-boot-image`(没有任何改 jar 的模块) | 空操作,日志写「没有过期产物」,什么都不删 |
| `build-consistency-dialog` + `stale-boot-image` | 弹窗没了,删 34 个过期产物(boot image + services oat) |
| `faceunlock/services-hooks` + `stale-boot-image`(不带 dialog) | 只删 services oat 那 6 个;boot image 没动 |
| 四个改 jar / 善后的模块全开 | 删 34 个,和 V66 一致 |

删除的集合取决于改动标记:framework.jar 改过 → 34 个;只有 services.jar 改过 → 6 个;都没改 → 0 个。

## 整组独立发布时要带什么

`patches/required/general/boot-kernel/stale-boot-image/` + `toolkit/lib/common.sh`(`mark_modified`/`was_modified`)。

## 版本

全开时删除集合与 V66 逐一相同(34 个)。V48 加删 boot image,见模块 README。
