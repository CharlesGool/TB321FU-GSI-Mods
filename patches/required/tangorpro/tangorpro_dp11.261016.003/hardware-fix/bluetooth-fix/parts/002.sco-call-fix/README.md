# bluetooth-fix(DP11)/sco-call-fix

## 做什么

修蓝牙通话:打开通话时一开始双方都听不到,或者麦克风用的是平板内置麦而不是耳机麦。

## 原理

V1.0 里 A2DP 走 `bluetooth_qti` 软件编码,PAL 里的 A2DP 设备从来不会"连上"。AHAL 下发 `A2dpSuspended=true` 时 PAL 返回 -22(设不进去),
但 `pal_get_param(PAL_PARAM_ID_BT_A2DP_SUSPENDED)` 依然成功并返回 `a2dp_suspended=0`。
`audio.primary.pineapple.so` 在开/切 SCO 前有一个检查:"必须先把 A2DP 挂起",看到"未挂起"就走错误分支(日志 `... if A2dp is not suspended`),
于是通话建立失败,或回落到平板麦克风。

4 处检查结构相同:
```
mov  w0, #0x10          ; PAL_PARAM_ID_BT_A2DP_SUSPENDED
bl   pal_get_param
cbnz w0, ok ; ... ldrb w8, [x8, #5]   ; a2dp_suspended
cbz  w8, <ERR "... if A2dp is not suspended">
```
`patch_ahal.py` 把最后这条 `cbz w8` 换成 `nop`,其余逻辑不动。

**怎么找这 4 处(换原厂固件也靠这个):** 脚本不写死偏移,按指令特征扫整个库:
一条 `cbz w8`(机器码 `34xxxx08`)紧接在 `ldrb w8,[x8,#5]`(`39401508`)后面,往前 12 条指令内有 `mov w0,#0x10`(`52800200`),并且两者之间有 `cbnz w0`(`350000e0`)。
在 ZUI 17.0.12.044 的库里正好 4 处:`StreamOutPrimary::Open`(0x547c4)、`StreamOutPrimary::RouteStream`(0x58f24)、`StreamInPrimary::Open`(0x5eb98)、`StreamInPrimary::RouteStream`(0x613b8)。
找到的个数必须正好是 4,否则拒绝并把找到的位置列出来。已核对过的库(`KNOWN` 表)还会再核对位置和记录一致。

库在 /vendor,GSI 改不了,所以补丁版用 `toolkit/lib/vendorbind.sh` 的 `vendor_bind_add` 登记(机制见 `toolkit/vendor-bind/README.md`):开机把它 bind 到
`/vendor/lib64/hw/audio.primary.pineapple.so`,原文件 sha256 对得上才盖。补丁文件标签 `vendor_file`。

## 改动清单

- `etc/vendor-bind/bt-sco-ahal-patch.file`(补丁后的 audio.primary,0644 root,`vendor_file`)
- `etc/vendor-bind/bt-sco-ahal-patch.bind`(描述符)
- 如果树里还没有,顺带装 `bin/vendor-bind.sh`、`etc/init/vendor-bind.rc`、`etc/vendor-bind/`(见 `toolkit/vendor-bind/README.md`)

## 输入(device.conf / conf.d/bluetooth.conf)

| 变量 | 说明 |
|---|---|
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像,从里面取 audio.primary |
| `BT_AHAL_REL` | 库在 vendor 里的相对路径,默认 `lib64/hw/audio.primary.pineapple.so` |

## 依赖和顺序

- 不依赖任何模块。开机用的 bind 脚本和 rc 由 `vendor_bind_add` 首次调用时自己装进镜像,和别的 vendor-bind 使用者共用一份。
- 原先是为"A2DP 走软件编码"准备的。DP11 版改回硬件卸载后保留它(用户 2026-11-09 要求),卸载方案下通话没有单独复测。

## 适用范围和换底包注意

换 vendor(原厂固件升级)按下面走,不用改脚本也不用手填 sha256:

1. 把 `STOCK_VENDOR_IMG` 指到新固件的 vendor,正常构建。构建时现取新库、按特征找、现算原文件 sha256 写进开机的 bind 描述符。
2. 脚本找到 4 处就直接打,日志里会列出每处偏移。找到的不是 4 处:说明新库里这段代码的结构变了。用反汇编看哪些分支报 "A2dp is not suspended"
   (搜字符串 `if A2dp is not suspended` 的引用,往回找 `pal_get_param(0x10)` 之后读 `[x8,#5]` 再 `cbz` 的位置),
   对照改 `patch_ahal.py` 里的 `EXPECT` 或特征常量。
3. 新库验证过后,把它的 sha256 和 4 个偏移补进 `KNOWN`(只是核对用,不加也能打)。
4. 库的路径变了(比如 SoC 换了名字)改 `BT_AHAL_REL`。

已知的两份库:ZUI 17.0.12.044(`d8fcef36…`)和 ZUI 17.5.10.170(`f468566…`)。
## 踩过的坑

- 最早对着 ZUI 17.5.10.170 的 vendor 做的。换到 9008 的 ZUI 17.0.12.044 时,audio.primary 逐字节差 20 字节(全在 ELF build-id 和两处版本标记),4 个补丁点指令完全一样,偏移没变,所以补丁本身能通用。
- **V66:SCO 补丁在 A15 设备上根本没生效。** V66 的开机 bind 脚本里 audio.primary 的原文件 sha256 是 ZUI 17.5.10.170 的 `f468566…`,
  而 A15 设备的真实 vendor 是 `d8fcef36…`,开机时对不上就被跳过,dmesg 里只有一行 skip。V66 镜像里放的补丁版 sha 是 `ecc37b9c…`,
  A15 重整后从 A15 vendor 现取现打的是 `ead809a9…`(完整 sha256 `ead809a9173799ec3abc1332a56c5b30b80d9831755881f712a2bf141f7191ca`)。
  上一轮重整时发现并修掉:原文件 sha256 现在由 `apply.sh` 对取出的库 `sha256sum` 现算后传给 `vendor_bind_add`,构建用哪份、开机核对哪份。
  已用 A15 的 vendor 镜像做过核对:描述符里是 `d8fcef36…`,和镜像里的库一致。

## 验证

蓝牙通话(如 Telegram)双方能听到、麦克风走耳机。`dmesg | grep vendor-bind` 有 `ok bt-sco-ahal-patch`,
不是 `skip bt-sco-ahal-patch: sha256 of ... is X, not the stock file ...`。
