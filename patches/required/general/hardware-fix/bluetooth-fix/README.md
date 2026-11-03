# bluetooth-fix — 蓝牙音频修复

> 一个补丁(`bluetooth-fix`),内部 3 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

## 解决什么问题

TB321FU 上的蓝牙有两个毛病:部分蓝牙耳机没声音或声音从平板出来(A2DP);蓝牙通话一开始双方听不到,或麦克风用的是平板内置麦(SCO)。
根源是高通的 A2DP 硬件 offload 在 AOSP 协议栈下起不来。修法是关掉 offload,A2DP 改走 vendor 的 `bluetooth_qti` 软件编码,
再去掉 AHAL 里因此失效的"A2DP 必须已挂起"检查。LE Audio 同样走 offload,在这个协议栈上不可用,一并关掉。

## 部分

| 部分 | 做什么 |
|---|---|
| [001.profile-props](parts/001.profile-props/) | 属性:关 A2DP offload、关 LE Audio 等,写进 product/etc/build.prop |
| [002.a2dp-offload-policy](parts/002.a2dp-offload-policy/) | 从原厂 vendor 的音频策略生成不走 offload 的版本,开机 bind 到 /vendor |
| [003.sco-call-fix](parts/003.sco-call-fix/) | 从原厂 vendor 的 audio.primary 生成去掉 4 处 SCO 检查的版本,开机 bind 到 /vendor |

三个部分修的是同一个问题,合起来才完整:关了 offload 才需要新的音频策略,换了策略需要 offload 已关;通话补丁是为"A2DP 走软件编码"这个前提准备的。所以合成一个补丁(2026-11-01),不再分开选。

后两个部分靠开机 bind 把补丁文件盖到 /vendor 上。这套机制是基础设施库(`toolkit/lib/vendorbind.sh` + `toolkit/vendor-bind/`):第一次调用 `vendor_bind_add` 时把开机脚本和 rc 装进镜像,之后只追加描述符,脚本和 rc 只有一份。机制和排错见 [toolkit/vendor-bind/README.md](../../../../../toolkit/vendor-bind/README.md)。

## 参数

`devices/tb321fu-a15/conf.d/bluetooth.conf`:`BT_POLICY_REL`、`BT_AHAL_REL`(vendor 里的文件路径),以及 vendor-bind 的标签参数(`VENDOR_BIND_*_LABEL`)。
另外需要 `device.conf` 提供 `STOCK_VENDOR_IMG`(原厂 vendor 镜像)和 `DEVICE`。

## 整组独立发布

带 `patches/required/general/hardware-fix/bluetooth-fix/` 和 `toolkit/`(含 `toolkit/lib/vendorbind.sh`、`toolkit/vendor-bind/`)。不含私有文件;用户需要自己提供原厂 vendor 镜像(`STOCK_VENDOR_IMG`),
补丁都是从它现取现打的。`patch_ahal.py` 的偏移是针对高通 pineapple 平台 ZUI 17.x 的 audio.primary,别的平台要重新找偏移。
