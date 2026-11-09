# bluetooth-fix(DP11)— 蓝牙音频修复

> 一个补丁,内部 3 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。只对 DP11 底包(`tangorpro_dp11.261016.003`)生效;
> 别的底包线仍用 `required/general/hardware-fix/bluetooth-fix`(V1.0,A2DP 软件编码、关 LE Audio),它们没在真机上验证过本方案。

## 解决什么问题

V1.0 关掉高通 A2DP 硬件卸载,改走 `bluetooth_qti` 软件编码,并关掉 LE Audio。DP11 上查明 A2DP 卸载本来能用:起不来是因为 V1.0 自己用改过的
音频策略盖掉了 primary 模块里的 `BT A2DP` 端口,并设了 `persist.bluetooth.a2dp_offload.disabled=true`。V2.0 改回原厂音频策略,A2DP 和 LE Audio(LC3)
都走 ADSP 硬件卸载,再修 vendor 在 LE 会话上把延迟单位报错(微秒当毫秒)导致的 VoIP 下行约 60 秒延迟。

## 部分

| 部分 | 做什么 |
|---|---|
| [001.profile-props](parts/001.profile-props/) | product/etc/build.prop:打开 A2DP 卸载和 LE Audio 卸载,关掉平板当耳机用的 LE 角色和高通不支持的 Pixel 特性 |
| [002.sco-call-fix](parts/002.sco-call-fix/) | 原厂 audio.primary 去掉 4 处"A2DP 必须已挂起"检查,开机 bind 到 /vendor(与 V1.0 相同) |
| [003.le-audio-latency](parts/003.le-audio-latency/) | 原厂 btaudio_offload_if.so 的 LE `peerDelayUs` 先 /1000 再上报,开机 bind 到 /vendor |

002、003 靠 vendor-bind 开机把补丁文件盖到 /vendor 上,原厂文件 sha256 对得上才盖。机制见 [toolkit/vendor-bind/README.md](../../../../../../toolkit/vendor-bind/README.md)。

## 参数

`devices/tb321fu-a15-dp11/conf.d/bluetooth.conf`:`BT_AHAL_REL`;可选 `BT_LE_LATENCY_REL`(默认 `lib64/btaudio_offload_if.so`);vendor-bind 的标签参数。
另外需要 `device.conf` 的 `STOCK_VENDOR_IMG` 和 `DEVICE`,构建机要有 `python3-pyelftools`、`python3-capstone`。

## 验证

2026-11-09 真机(Galaxy Buds 3 Pro):

- BTtest-v1.7:A2DP AAC 卸载(`Offload started`,软件编码 TxQueue 0/0/0,primary/deep_buffer → BT_A2DP)。
- test-v1.8:LE Audio LC3 ADSP 卸载,左右耳都有声音;TG 语音实时,`sink_latency` 为毫秒值。
- HFP/SCO 通话沿用 002,卸载方案下没有单独复测。

## 已知

- 老配对的双模耳机打开"LE 音频"后要重启一次蓝牙,另一只耳机经 CSIP 自动入组;若第二只在推流中途入组,组会被置为 inactive,再重启一次蓝牙恢复,只发生一次。
- aptX Adaptive / LHDC 不可行:Pixel 栈没有 aptX Adaptive 编码,高通 vendor 没有 LHDC 编码器。
- 以前手动 `setprop persist.bluetooth.a2dp_offload.disabled true` 过的设备,保数据刷机后 /data 里的值仍优先,要 `setprop ... false` 再重启。
