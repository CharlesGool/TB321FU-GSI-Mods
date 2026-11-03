# perf/cpu-freq — CPU 各簇频率上下限

`perf cpu status | set <簇号|all> <min|max> <kHz|N%|stock> | reset`。每个 cpufreq policy(TB321FU 是 0/2/5/7,调速器 walt,节点本来就是 0666)单独调 `scaling_min_freq` / `scaling_max_freq`。

- 值可以是 kHz 数值(夹在 `cpuinfo_min/max` 之间)、`N%`(可用档位里不超过 最高档×N% 的最大一档)、`stock`(出厂值,同时清掉记忆)。
- 写入顺序保证任何时刻 `min <= max`(升 max 先升 max,降 max 先降 min);要写的 min 大于 max 直接报错、不写。
- 回包里 `readback` 是写完读回的实际值,内核夹成相邻档位时和请求值不同。
- 每约 30 秒核对一次,被改回去就重写。

整体说明见 [`../README.md`](../../README.md)。依赖 `perf/node-access`。
