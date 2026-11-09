# bluetooth-fix(DP11)/le-audio-latency

修 LE Audio 下 VoIP(TG/X 语音)下行约 60 秒延迟、X 视频偶发播放错误。

`/vendor/lib64/btaudio_offload_if.so` 的 `audio_get_a2dp_sink_latency()`:A2DP 会话按毫秒返回;LE 会话(AIDL SessionType 6/7)直接把
`LeAudioConfiguration.peerDelayUs`(微秒)截成 16 位返回,PAL 当毫秒用。124000 µs → `& 0xFFFF` = 58464 → 系统认为下行延迟 58.5 秒,
应用按播放位置节流,语音在抖动缓冲里积压。Pixel AOSP 栈按 AIDL 规范报微秒,所以只在 GSI 上暴露。

`patch_btaudio_le_latency.py` 在两个 LE 分支取到 `peerDelayUs` 后加 `udiv /1000`;空间来自原代码里冗余的 entry 地址重算(`mov #0x1e0; umaddl`)。
按指令模式定位,命中不唯一就中止,能识别已打补丁。ZUI 17.0.12.044:改 64 字节 @0x12ea4,原 `21a117e6…e473` → `d72aee9e…747f`。
依赖 pyelftools、capstone(4.x 打 `movz`、5.x 打别名 `mov`,工具两种都认)。补丁版用 `vendor_bind_add` 登记,开机 bind,原文件 sha256 对得上才盖。

2026-11-09 真机:先热补丁验证,再打进 test-v1.8 上机验证,TG 语音实时。

刷机后:`dmesg | grep vendor-bind` 有 `ok bt-le-audio-latency`;`logcat | grep sink_latency` 是 `124` / `47` 这类毫秒值,不是 `58464` / `47000`。
