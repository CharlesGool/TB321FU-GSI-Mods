# gsi-hide — 去掉 GSI / 虚拟机痕迹

> 一个补丁(`gsi-hide`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

让检测软件(Duck Detector、春秋 Native Check、Hunter、Momo 这类)从属性和标签上看不出这是 GSI。只改属性和 SELinux 标签,不删文件(删 GSI 工具留下的文件在 [slim/gsi-traces](../../../tangorpro/tangorpro_ap3a.241005.015/slim/gsi-traces/))。

| 部分 | 做什么 |
|---|---|
| [partition-verified](parts/001.partition-verified/) | `partition.*.verified` 改成 1 |
| [qemu-prop-label](parts/002.qemu-prop-label/) | 去掉 `qemu_sf_lcd_density_prop` 标签(虚拟机痕迹) |

互相独立,顺序随意。SELinux 开机即 Enforcing 是另一件事,在 [selinux](../../../tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/)。底包不同时都有"没有就跳过"的处理。
