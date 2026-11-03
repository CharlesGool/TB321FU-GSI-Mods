# perf/node-access — 性能调节的公共部分

给 免 root 核心加 `perf` 命令(按子命令分发给 `perf/*` 各模块),给 `heraldctl` 加 `perf` 子命令。提供:

- `herald_perf_read` / `herald_perf_write`(写完读回:写不进返回 1,读回不同返回 2);
- 配置记忆 `$STATE/perf.conf`(`cpu.<簇>.min|max`、`gpu.min|max`、`profile`、`game_profile`);
- "出厂值" `$STATE/perf.stock`(开机后第一次要改前读到的,带开机 id);
- 百分比换算 `herald_perf_pick`(不超过 最高档×N% 的最大一档)、`herald_perf_resolve`(stock | N% | 数值);
- 空闲调度:每约 30 秒让各模块的 `heraldp_perf_reapply_<名字>` 核对一次。模块把名字追加进 `PERF_SLOW_MODS`(这里不赋初值,因为插件按字母序加载)。

整体说明、档位、没核对的项见 [`../README.md`](../../README.md)。依赖 `herald-core`;其他 `perf/*` 都要求它在前面。
