# video-freeze-fix/libgui-surface-gen

## 做什么

`/system/lib64/libgui.so` 里 `Surface::disconnect()` 的 `mGenerationNumber = 0;`(`str wzr,[xN,#0x3b0]`)→ `nop`,
恢复 A16 及以前的行为:disconnect 不清 Surface 缓存的 generation。DP11:文件偏移 `0x11c28c`,`7f b2 03 b9` → `1f 20 03 d5`。

## 为什么

A17 的 libgui 新增了"auto generation update":`Surface::attachBuffer` 用 Surface 缓存的 generation 覆盖缓冲区自己的,
而 `disconnect` 会把缓存清零。`MediaCodec::connectToSurface` 是"先设 generation N → disconnect → connect",结果缓存 = 0、BufferQueue = N。
HIDL Codec2 客户端(`OutputBufferQueue`,我们的高通 A14 vendor 走这条)切 Surface 时 attach 的每个缓冲都被盖成 0,全部被拒,
vendor 却以为迁移成功,缓冲池被幽灵槽位占满 → 不出帧。Pixel 原机走 AIDL `GraphicsTracker`,它显式 `setAutoGenerationUpdate(false)`,所以没事。
详见[调研记录](https://github.com/CharlesGool/gsi-codec2-video-freeze-guide/blob/main/doc/research.md)第 2~6 节。

## 定位(`patch_libgui_surface_gen.py`)

从 `Surface::setGenerationNumber` 里唯一的 32 位 STR 推出 `mGenerationNumber` 字段偏移,再在 `Surface::disconnect` 里找
`str wzr,[xN,#偏移]`,必须恰好 1 处才改。0 处 = 这个 libgui 没有这段逻辑(A15/A16),本部分跳过;其它情况中止构建。

## 副作用

- `mAutoGenerationUpdate = true` 那条照常执行;AIDL 路径本来就关了自动覆盖,不受影响。
- 会设非零 generation 的只有 MediaCodec,它在 `disconnectFromSurface()` 里自己 `setGenerationNumber(0)` 复位,不依赖 disconnect 清零。
- 只改 64 位库;32 位 `lib/libgui.so` 只有 32 位进程用,几乎没有 32 位 app 播视频。
