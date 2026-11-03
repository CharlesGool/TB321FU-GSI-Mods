# bluetooth/profile-props

## 做什么

关掉 A2DP 硬件 offload,关掉 LE Audio 相关的蓝牙 profile,让蓝牙耳机走经典蓝牙 + 软件编码。

## 原理

属性写进 `product/etc/build.prop`,product 分区最后加载,能盖住 vendor 里的值。`props.py` 的规则:已有的 key 就地改值,没有的追加到末尾(带一行注释 `# TB321FU: A2DP 走 vendor bluetooth_qti 软件编码, 关闭 LE Audio`)。

属性清单在 `bt.prop`,分三类:

- **A2DP**:`persist.bluetooth.a2dp_offload.disabled=true`、`persist.bluetooth.bluetooth_audio_hal.disabled=false`。TB321FU 的高通 A2DP 硬件 offload 在 AOSP 协议栈下起不来(`session ready = 0`),PAL 忽略切到 A2DP 的路由,所以关掉,改走 vendor 的 `bluetooth_qti` 软件编码。关了 offload 后协议栈要找对应的音频策略,那份策略由 `bluetooth/a2dp-offload-policy` 提供。
- **LE Audio**:`bluetooth.profile.bap.*`、`csip`、`hap`、`vcp`、`vc`、`mcp`、`ccp`、`tbs`、`ro.bluetooth.leaudio_switcher.supported`、`ro.bluetooth.leaudio.le_audio_connection_by_default` 全部设成 false。LE Audio 也走高通 offload,在 AOSP 协议栈下用不了(打开后 PAL 报 `a2dp handle is not identified`),vendor 策略里也没有软件路径的 BLE 端口。关掉后双模耳机只走经典蓝牙,这和原厂 ZUI 的默认一致。
- **Pixel 专用特性**:`persist.bluetooth.opus.enabled=false`、`bluetooth.core.le_audio.codec_extension_aidl.enabled=false`、`bluetooth.hfp.swb.supported=false`,高通 vendor 不支持。

## 改动清单

- `product/etc/build.prop`:改了若干个已有 key,追加其余 key(原底包里 LE Audio 相关的 7 个属性和 opus 是 true,就地改成 false;原来没有的 8 个追加到末尾)。

## 输入

无(`bt.prop` 在模块目录里)。

## 依赖和顺序

无依赖,没有顺序要求,可以单独选。效果上和 `bluetooth/a2dp-offload-policy` 配合:只关 offload 不换策略,A2DP 没有可用的路由;只换策略不关 offload,协议栈不会走软件编码。想要完整效果就两个都选。

## 适用范围和换底包注意

- 要求底包有 `product/etc/build.prop`。
- 换 GSI 后属性名可能变(AOSP 版本不同),`props.py` 对没出现过的 key 会追加,不会报错,换大版本后要核对协议栈是否还认这些名字。

## 踩过的坑

- 不能用 `sudo sed -i` 改 build.prop,会换 inode 丢标签(V60/V64);统一走 `common.sh` 的 `edit`。

## 验证

刷机后 `getprop persist.bluetooth.a2dp_offload.disabled` 为 true;蓝牙耳机听歌有声音、声音在耳机上。
