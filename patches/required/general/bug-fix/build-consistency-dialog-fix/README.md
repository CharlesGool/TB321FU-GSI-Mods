# build-consistency-dialog-fix — 去掉开机「设备内部出现了问题」弹窗

## 做什么

改 `framework.jar`,把 `android.os.Build.isBuildConsistent()` 短路成 `return true`,开机不再弹「设备内部出现了问题」对话框。

## 原理

GSI 的 framework(system)和联想 vendor 不是同一套编译产物。`IS_TREBLE_ENABLED=true` 时 `Build.isBuildConsistent()` 会调 `VintfObject.verifyBuildAtBoot()` 比较 framework compatibility matrix 和 vendor manifest(HAL/SELinux/kernel 版本等),对不上就返回 false。唯一调用方 `ActivityTaskManagerService$LocalService.showSystemReadyErrorDialogsIfNeeded`(在 services.jar 里)在非 eng 构建上据此弹「设备内部出现了问题」(smali 里的日志 `Build fingerprint is not consistent, warning user`)。

全系统 grep 过:整个镜像只有 `framework.jar` 这一处 `isBuildConsistent()` 实现、`services.jar` 一处调用,没有第二条路径。这个方法只管这条提示,**不是 AVB/dm-verity/SELinux 那层真校验,也不参与 Play Integrity attestation**。所以在方法开头直接 `return true` 最干净(不删调用链、副作用最小,见兄弟工程 `doc/09-DECOMPILE-PATCH-METHOD.md`)。

补丁(`patch_build_consistent.py`)只动 `Build.smali` 里 `isBuildConsistent()` 的方法体。它所在的那一份 dex(本底包是 classes3.dex)用 apktool 回编版换回去,framework.jar 的其它 dex 和所有非 dex 条目原样不动(`jarpatch.py assemble --swap`)。

## 改动清单

- **改** `system/framework/framework.jar`:换 Build 所在的那份 dex(`isBuildConsistent` → return true),其它 dex 不动。
- 改完调用 `mark_modified framework/framework.jar`,让 `stale-boot-image` 知道 boot image 过期了。
- 本模块**不删**任何预编译产物。改了 framework.jar 以后不配 `stale-boot-image` 的话,boot image 过期没人清(后果见那边的 README)。

## 输入

| 变量 | 说明 |
|---|---|
| `APKTOOL_JAR` | apktool 2.12.1(反编译/回编 framework.jar) |

需要 `java`、`zipalign`。

## 依赖和顺序

- 不依赖其他模块,可以单独启用。和 `faceunlock/*` 各模块互不影响(它们不碰 framework.jar,本模块不碰 services.jar)。
- 要排在 `stale-boot-image` **前面**;排在后面本模块会直接报错。

## 适用范围和换底包注意

framework.jar 从当前底包现取现改。`isBuildConsistent()` 的方法签名(含 `greylist-max-o` 修饰符)和「开头两条 `const/4 v0,0x1` + `return v0`」是靠 `patch_build_consistent.py` 的正则匹配的。会 `die` 的情况:

- 找不到 `android/os/Build.smali` 里的 `isBuildConsistent()Z`(方法被改名/移走)。
- 补丁没落到,或 Build.smali 里已经有补丁标记(底包已打过)。
- 回编后的 `isBuildConsistent` 不是直接 `return true`,或回编后 smali 与补丁结果不等价。

## 踩过的坑(带版本)

- **V47-PIF**:复用兄弟工程 V8.3 的 `isBuildConsistent()` 补丁方法去弹窗,动手前在本工程镜像上独立确认过命中位置(没假设和 BP1A 项目一样)。实机通过。
- **V47→V48**:换上这个补丁后 Hunter 报 memfd 告警 —— 是 framework.jar 补丁的连带,不是补丁本身的问题。修法是 `stale-boot-image`(原来在同一个模块里),见那边的 README。

## 验证

离线(已在 V66 底包上验证):
- 产物 framework.jar 的 **全部 5 份 dex 和 V66 的 framework.jar 逐字节相同**(只有 Build 所在的 classes3.dex 是补丁版,其余原样)。整个 jar 文件的 sha256 与 V66 不同(zip 里的对齐填充不同),条目名、时间戳、压缩方式、CRC 一致。
- 产物 framework.jar 再反编译,`isBuildConsistent()` 不再调 `VintfObject.verifyBuildAtBoot`、直接 `return 1`;Build.smali 与补丁后语义一致(`jarpatch.py smali-equiv`)。

上机:开机不再弹「设备内部出现了问题」。
