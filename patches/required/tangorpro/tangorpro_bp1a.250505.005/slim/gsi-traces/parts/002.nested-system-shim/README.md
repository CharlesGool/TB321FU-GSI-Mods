# gsi-traces / 002.nested-system-shim

删掉整棵嵌套的 `/system/system/` phh 垫片树。

BP1A 底包经 MysticGSI cli.py(phh-treble 系)转换,把一整套 phh 垫片塞进了嵌套 `/system/system/`:
`bin/`(phh-on-boot.sh、phh-on-data.sh、rw-system.sh、busybox_phh、vndk-detect、bootctl、permissiver.sh)、
`etc/init/`(vndk.rc、mystic.rc、permissiver.rc)、`etc/`(fstab.postinstall、两个 audio policy xml)、
`phh/`(各厂商按键布局/NFC 配置)、`ph/`。

## 为什么整棵删是安全的

运行时 init 只扫 `/system/etc/init`(外层),不扫 `/system/system/etc/init`。实测:
- 外层 `system/etc/init` 里没有任何 phh/mystic/vndk/permissiver 的 rc;
- 没有任何 init rc / build.prop import 引用 `/system/system/` 路径;
- `system/system` 是普通目录,不是让它变活的符号链接。

所以这棵树在运行时完全不加载,纯粹是转换器留下的检测痕迹(AP3A-Mystic 底包根本没有嵌套 `system/system`)。
AP3A 版 gsi-traces 要逐文件保留顶层 phh 里起作用的 `rw-system.sh`/`phh_on_boot`;BP1A 这棵是死的,整棵删。

开机 Enforcing 不依赖这里:由 `bug-fix/selinux/fix` 的顶层 `init.enforce.rc` 保证(gsi-traces 先跑,把嵌套
`permissiver.rc` 一并删了,selinux/fix 再跑时跳过)。
