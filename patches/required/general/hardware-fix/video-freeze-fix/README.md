# video-freeze-fix — 视频画面卡住修复

> 一个补丁(`video-freeze-fix`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。完整排查过程(logcat、uprobe、反汇编、对照 AOSP 源码)见[调研记录](https://github.com/CharlesGool/gsi-codec2-video-freeze-guide/blob/main/doc/research.md)。唯一来源是 [tb321fu-video-freeze-patch](https://github.com/CharlesGool/tb321fu-video-freeze-patch) 的 `patch/`,TB321FU-GSI-Mods 里的是同步副本。

## 解决什么问题

X(以及其他会预加载 / 切换 Surface 的播放器)刷视频时:**声音继续,画面定格**,拖一下进度条恢复。同一个现象背后有两个独立原因,两部分都要打:

| 部分 | 改哪 | 原因 | 触发 |
|---|---|---|---|
| [001.codec2-alloc-retry](parts/001.codec2-alloc-retry/) | `/vendor/lib64/libqcodec2_v4l2codec.so`(开机 bind) | 高通 vendor 解码器申请输出缓冲超时后,"距上次输入 >1s 就放弃",而输入槽已被它自己占满 → 永久死锁 | 下一个视频预加载完、停留 >1 秒再滑过去(刷视频最常见)。与框架版本无关,A15/A17 都会 |
| [002.libgui-surface-gen](parts/002.libgui-surface-gen/) | `/system/lib64/libgui.so` | A17 的 `Surface::disconnect` 会清零缓存的 generation,HIDL Codec2 切 Surface 时缓冲迁移全部被 BufferQueue 拒绝 | 播放中切换 Surface(全屏/内嵌切换、播放器复用)。只有 A17 框架有;A15/A16 的 libgui 自动跳过 |

两处都只改 1 条 AArch64 指令(4 字节)。两个工具都不写死偏移:按符号 + 指令模式定位,命中不唯一就中止构建。

## 镜像里的改动

- `lib64/libgui.so`:`Surface::disconnect` 里的 `str wzr,[xN,#<mGenerationNumber>]` → `nop`(保留原属主、权限、SELinux 标签)。底包没有这条指令就不动。
- `etc/vendor-bind/video-qcodec2-alloc-retry.file`(补丁版 `libqcodec2_v4l2codec.so`,0644 root,`vendor_file`)和 `.bind` 描述符;
  树里还没有的话顺带装 `bin/vendor-bind.sh`、`etc/init/vendor-bind.rc`(见 [toolkit/vendor-bind/README.md](https://github.com/CharlesGool/TB321FU-GSI-Mods/blob/main/toolkit/vendor-bind/README.md))。

vendor 分区本身不改,所以不用重做 vendor 的 hashtree / vbmeta;补丁版 .so 随 system 走,开机 post-fs 阶段(codec 服务启动之前)核对原厂文件 sha256 后 bind 上去,对不上就不盖(安全回退到原厂行为)。

## 输入

- `device.conf`:`STOCK_VENDOR_IMG`(原厂 vendor 镜像,现取 v4l2codec 库)、`DEVICE`(vendor-bind 设备守护)。
- 构建机要有 `python3-pyelftools`(两个工具都用它读 `.dynsym`)。
- 可选 `VF_QCODEC2_REL`:库在 vendor 里的相对路径,默认 `lib64/libqcodec2_v4l2codec.so`。设备上没有 32 位版本;32 位 `lib/libgui.so` 只有 32 位进程用,不改。

## 换底包 / 换固件

- 换 Pixel 底包:直接构建。`002` 的日志会写"未打补丁 → 已改"或"跳过(不需要)";如果 Google 修了(disconnect 不再清零),自动跳过。
- 换 vendor(原厂固件):直接构建,原文件现取、sha256 现算。工具找不到唯一的 `ldr/cbz` 成对位置就中止,去反汇编 `QC2V4l2Decoder::DecoderOutputAllocator::handleOutputBufferAllocation` 的 `C2_TIMED_OUT` 分支重新确认。

## 验证

- 离线:构建日志里两部分都打印改动偏移和前后 sha256;`cmp -l` 只允许 1~4 字节差异,复查 `--check` 状态必须翻转。
- 当前输入(ZUI 17.0.12.044 vendor、DP11 底包)的已知值:

  | 文件 | 原文件 sha256 | 补丁后 sha256 | 偏移 |
  |---|---|---|---|
  | `libgui.so`(DP11) | `222ca5e3…3007` | `9a9ec193…4b4a` | `0x11c28c` |
  | `libqcodec2_v4l2codec.so` | `e328076b…df25` | `faaeaa8c…a35c` | `0x16e078` |

- 真机(进程内存热补丁):X 进程里 migration N/N;codec 服务里必现场景 4/4、连滑 25 个、长停留 4/4 都不卡,见调研记录第 7、8.5 节。
- 真机(刷进镜像):2026-11-09 刷 DP11 `BTtest-v1.7-cust_bebug`(含 V1.0 两部分),X 刷视频不再出现画面定格。
- 复查方法:

  ```bash
  adb shell dmesg | grep vendor-bind            # 应有 ok video-qcodec2-alloc-retry: /vendor/lib64/libqcodec2_v4l2codec.so
  adb logcat -c   # 刷 X 视频几分钟,包括在一个视频停留 >10 秒再滑走、切全屏
  adb logcat -d | grep -E "generation number mismatch|remote graphic buffer migration|Allocating output buffer timedout"
  ```

  通过标准:没有 `generation number mismatch`;`remote graphic buffer migration N/N` 全部成功;
  不再出现 `Allocating output buffer timedout ... elapsed since last input`(补丁后走重试分支,不打这条);刷视频不再卡画面。
