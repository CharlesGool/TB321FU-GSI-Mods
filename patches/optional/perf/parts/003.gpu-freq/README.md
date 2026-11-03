# perf/gpu-freq — GPU 频率上下限

`perf gpu status | set <min|max> <Hz|NMHz|N%|stock> | reset`。写 `/sys/class/kgsl/kgsl-3d0/devfreq/{min_freq,max_freq}`(Hz),可用档位来自 `available_frequencies`。规则同 [cpu-freq](../002.cpu-freq/):写完读回、`min <= max`、出厂值、每约 30 秒核对。

**节点只在 root 下可读写**(shell 读不到),这台没验证过节点名;没有这个节点时返回 `err perf 这台机器没有 GPU 频率节点`。整体说明见 [`../README.md`](../../README.md)。依赖 `perf/node-access`。
