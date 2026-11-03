# bluetooth/a2dp-offload-policy

## 做什么

换一份不走高通 offload 的音频策略,让 A2DP 耳机的声音走软件编码,耳机里有声音。

## 原理

TB321FU 原厂的 `sku_pineapple` 音频策略里,蓝牙 A2DP 输出口(`BT A2DP Out / Headphones / Speaker`)是 offload 口,走高通硬件。
这条路在 AOSP 协议栈下起不来(`session ready = 0`),PAL 忽略切到 A2DP 的路由,结果耳机没声音或声音从平板扬声器出来。
`bluetooth/profile-props` 把 offload 关掉之后,需要一份没有 offload 口的策略。

`make_policy.py` 从**构建时现取的原厂策略**改出来(不内置策略文件):

1. primary 模块里删掉 BT A2DP Out / Headphones / Speaker 三个设备口和它们的三条路由。
2. 把只含助听器的 `bluetooth_qti_hearing_aid_audio_policy_configuration.xml` include 换成完整的 `bluetooth_qti_audio_policy_configuration.xml`(A2DP + 助听器,由 vendor 的 `audio.bluetooth_qti.default.so` 做软件编码)。

脚本按 `(设备口, 路由, include) = (3, 3, 1)` 核对,数量对不上就停,不会悄悄出一份残缺的策略。

策略在 /vendor,GSI 改不了,所以用 `toolkit/lib/vendorbind.sh` 的 `vendor_bind_add` 登记(机制见 `toolkit/vendor-bind/README.md`):开机在 post-fs 把它 bind 到
`/vendor/etc/audio/sku_pineapple/audio_policy_configuration.xml`,原文件 sha256 对得上才盖。补丁文件标签是 `vendor_configs_file`(和被盖的文件一致)。

## 改动清单

- `etc/vendor-bind/bt-a2dp-offload-policy.file`(补丁后的策略,0644 root,`vendor_configs_file`)
- `etc/vendor-bind/bt-a2dp-offload-policy.bind`(描述符)
- 如果树里还没有,顺带装 `bin/vendor-bind.sh`、`etc/init/vendor-bind.rc`、`etc/vendor-bind/`(见 `toolkit/vendor-bind/README.md`)

## 输入(device.conf / conf.d/bluetooth.conf)

| 变量 | 说明 |
|---|---|
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像,从里面取策略 |
| `BT_POLICY_REL` | 策略在 vendor 里的相对路径,默认 `etc/audio/sku_pineapple/audio_policy_configuration.xml` |

## 依赖和顺序

- 不依赖任何模块。开机用的 bind 脚本和 rc 由 `vendor_bind_add` 首次调用时自己装进镜像;和 `sco-ahal-patch` 一起启用时只装一份,顺序随意。
- 和 `bluetooth/profile-props` 成套使用(见那边的说明)。和 `bluetooth/sco-call-fix` 互不依赖,可以单独启用。

## 适用范围和换底包注意

换 vendor(原厂固件升级):策略的结构可能变。`make_policy.py` 数量对不上会停,这时对照新策略改正则;
原文件的 sha256 是现算的,不用手动更新。
策略文件路径变了(比如 SoC 换了 sku 名)改 `BT_POLICY_REL`。

## 踩过的坑

- 最早是靠 AOSP 的 `audio_policy_configuration_a2dp_offload_disabled.xml` 查找机制放策略,搜索路径里有没有 /system/etc 没法确认,所以直接 bind 盖住 vendor 的原路径。
- V66 的 bind 脚本里 audio.primary 的 sha256 对成了旧固件的值(见 `bluetooth/sco-call-fix`)。现在两个补丁的原文件 sha256 都是构建时现算。

## 验证

蓝牙耳机听歌有声音、声音在耳机上。`dmesg | grep vendor-bind` 有 `ok bt-a2dp-offload-policy`。
