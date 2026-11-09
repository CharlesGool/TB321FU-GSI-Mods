# bluetooth-fix(DP11)/profile-props

## 做什么

A2DP 和 LE Audio(LC3)走高通 ADSP 硬件卸载;关掉平板当耳机用的 LE 角色和高通 vendor 不支持的 Pixel 特性。

## 原理

属性写进 `product/etc/build.prop`(product 晚于 vendor 加载,能盖住 vendor 的值)。`props.py`:已有的 key 就地改值,没有的追加到末尾
(带一行注释 `# TB321FU: A2DP 和 LE Audio(LC3)走高通 ADSP 硬件卸载`)。

- **A2DP**:`persist.bluetooth.a2dp_offload.disabled=false`。vendor 已声明 `ro.bluetooth.a2dp_offload.supported=true` 和 `persist.bluetooth.a2dp_offload.cap`,
  原厂音频策略的 primary 模块本来就有 `BT A2DP Out` 端口,不需要再改策略。
- **LE Audio**:vendor build.prop 里 LE profile 本来是 true,被 Pixel tangorpro 的 product 段(平板没有 LE Audio)改成了 false。这里改回 true
  (`bap.unicast.client`、`csip.set_coordinator`、`vcp.controller`、`mcp.server`、`ccp.server`、`hap.client`、`bap.broadcast.assist/source`),
  并加 `ro.bluetooth.leaudio_offload.supported=true`、`persist.bluetooth.leaudio_offload.disabled=false`、`persist.bluetooth.leaudio.toggle_visible=true`(耳机详情里出现"LE 音频")。
  `ro.bluetooth.leaudio.le_audio_connection_by_default=false`:双模耳机默认仍走经典蓝牙,和原厂 ZUI 一致。
- **不开**:`bap.unicast.server`、`vc.server`、`tbs.server`(平板当耳机用的角色)、`ro.bluetooth.leaudio_switcher.supported`;
  `bluetooth.core.le_audio.codec_extension_aidl.enabled=false`(vendor 蓝牙音频 provider 是 V3,没有 V4 的 codec extension)、`persist.bluetooth.opus.enabled=false`、`bluetooth.hfp.swb.supported=false`。

## 验证

刷机后 `getprop persist.bluetooth.a2dp_offload.disabled` 为 false,`getprop ro.bluetooth.leaudio_offload.supported` 为 true;
`dumpsys bluetooth_manager` 里 `A2dpOffloadEnabled: true`,LE 下 `Codec location: ADSP`。
