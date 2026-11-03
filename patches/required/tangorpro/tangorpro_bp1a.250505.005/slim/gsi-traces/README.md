# slim/gsi-traces(BP1A 版)— GSI 转换器留下的痕迹

> 一个补丁(`slim/gsi-traces`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。

BP1A 底包是官方 Pixel factory GSI 经 **MysticGSI cli.py**(phh-treble 系)转成的。它留下两处痕迹:

| 部分 | 删什么 | 大小 |
|---|---|---|
| [mystic-vendor-overlays](parts/001.mystic-vendor-overlays/) | `/system/mystic`(顶层,没人引用的 tangorpro vendor overlay) | 276K |
| [nested-system-shim](parts/002.nested-system-shim/) | 整棵嵌套 `/system/system/` phh 垫片树(bin/etc/phh/ph) | 约 2M |

## 为什么和 AP3A 版结构不同

AP3A(Mystic 社区底包)的 phh 垫片在**顶层** `/system/{bin,phh,etc/init}`,而且其中 `rw-system.sh`、
`phh_on_boot`、`vndk-detect` 等是**起作用的**(通用逻辑:vndk tmpfs、A/B 槽标记、热点 hostapd 属主等),
所以 AP3A 版只逐文件外科切除死件(按键布局、远程 adb、属性处理脚本、mystic logcat),保留起作用的部分。

BP1A(MysticGSI cli.py)把**一整棵** phh 垫片塞进**嵌套** `/system/system/`。实测这棵树在运行时完全是死的:
init 只扫 `/system/etc/init`(外层),不扫 `/system/system/etc/init`;外层 `etc/init` 里没有任何
phh/mystic/vndk/permissiver,也没有任何文件引用 `/system/system/` 路径。所以它纯粹是检测痕迹
(AP3A 底包根本没有嵌套 `system/system`),直接整棵删掉,不需要像 AP3A 那样保留什么。

嵌套树里的 `permissiver.rc`(`setenforce 0`)同样是死的;开机 Enforcing 由 `bug-fix/selinux/fix` 的
顶层 `init.enforce.rc` 保证(本补丁先跑,把嵌套 permissiver 一并删了,selinux/fix 再跑时就跳过)。
