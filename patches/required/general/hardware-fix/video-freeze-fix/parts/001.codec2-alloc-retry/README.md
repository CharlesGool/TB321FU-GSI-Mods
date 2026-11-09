# video-freeze-fix/codec2-alloc-retry

## 做什么

`/vendor/lib64/libqcodec2_v4l2codec.so` 里 `QC2V4l2Decoder::DecoderOutputAllocator::handleOutputBufferAllocation()` 的超时(`C2_TIMED_OUT`)分支:

```
ldr x9, [x8, #0x280]      ; 阈值 private_max_retry_alloc_output_timeout(=1000ms)
cbz x9, REPOST            ; 阈值为 0 = 不限时,继续重试
```
把 `cbz` 换成无条件 `b REPOST`:超时后永远继续重试(150ms 一次),不再"距上次输入 >1s 就放弃"。
等效于把 vendor 自带的阈值设成 0,是高通代码里本来就支持的模式;真正的分配错误(非 110)仍走原来的报错路径。

## 为什么

X(ExoPlayer)给下一个视频提前建好解码器并预加载:解码器把全部输出缓冲解满,手里还压着约 10 个输入(输入槽总共就 10 个)。
它每 150ms 重试一次申请输出缓冲,超过 1 秒没收到新输入就停止重试。用户滑过去后 X 归还了缓冲,但 vendor 已经不再申请;
X 想送新输入,可输入槽全在 vendor 手里 → 谁也等不到谁,画面永久定格。拖进度条 = flush,所以恢复。详见[调研记录](https://github.com/CharlesGool/gsi-codec2-video-freeze-guide/blob/main/doc/research.md)第 8 节。

## 定位(`patch_qcodec2_alloc_retry.py`)

不写死偏移:在 `handleOutputBufferAllocation` 函数体里找 `ldr Xt,[Xn,#K]; cbz Xt,T` 与 `ldr Xs,[Xm,#K-8]; cbz Xs,T` 成对出现
(阈值字段 0x280 / 上次输入时间 0x278,跳到同一个重试块),必须恰好 1 处。ZUI 17.0.12.044:文件偏移 `0x16e078`,`89 16 00 b4` → `b4 00 00 14`。

库在 /vendor,GSI 改不了,补丁版用 `vendor_bind_add` 登记,开机 bind 到原路径,原文件 sha256(构建时现算)对得上才盖。

## 代价

预加载后一直没轮到播放的解码器会每 150ms 醒一次(一次 fence 等待),直到被释放,CPU 开销可忽略。
