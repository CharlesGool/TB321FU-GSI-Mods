# perf/profiles — 一键切档

`perf profile [status] | powersave | balanced | performance`。省电 = CPU/GPU 最高频限到 60%,性能 = CPU 最低频抬到 40%,均衡 = 全部出厂值(详见 [`../README.md`](../../README.md))。手动 `perf cpu set` / `perf gpu set` 之后档位显示 `custom`。

对别的模块提供:`herald_perf_profile_apply <名字>`;`herald_perf_snapshot` / `herald_perf_restore_snapshot <文件>`(临时切档、之后把 cpu/gpu 设置和档位名原样恢复,`perf/game-boost` 用)。

依赖 `perf/cpu-freq`;`perf/gpu-freq` 装了就一起调 GPU,没装或没节点只调 CPU。
