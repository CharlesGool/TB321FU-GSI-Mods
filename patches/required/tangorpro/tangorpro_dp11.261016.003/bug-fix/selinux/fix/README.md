# selinux/fix — SELinux 修复

> 一个补丁(`selinux/fix`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。一个改 system,一个改 boot——构建时 GSI 和原厂固件在同一个工作区里,一个补丁两边都能改。依赖和说明见 `patch.conf`,每个部分的原理见它自己的 `README.md`。

Mystic GSI 开机大半时间是 Permissive(permissiver 在后面才翻转),检测软件能看出来。两处一起改,SELinux 从内核起就是 Enforcing,用户态不再有翻转。

| 部分 | 改哪里 | 做什么 |
|---|---|---|
| [001.enforce-at-init](parts/001.enforce-at-init/) | system | 删 Mystic 的 permissiver,early-init 里 `setenforce 1` |
| [002.kernel-enforcing](parts/002.kernel-enforcing/) | boot | 内核命令行加 `enforcing=1 selinux=1`(登记给 [boot-assemble](../../../../../general/boot-kernel/boot-assemble/) 写进 boot.img) |

Enforcing 下排查问题要用的 adb logcat 权限在单独的补丁 [selinux/shell-logcat](../../../../../../debug/shell-logcat/)。别的 GSI 本来就 Enforcing 时,001 会跳过。
