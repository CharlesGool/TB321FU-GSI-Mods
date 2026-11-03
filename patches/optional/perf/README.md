# perf — 性能调节

> 一个补丁(`perf`),内部 5 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

调 CPU 各簇和 GPU 的**频率上下限**,一键切省电/均衡/性能档,游戏模式里进游戏自动切性能档。五个部分,都是 免 root 核心插件(`heraldctl perf …`),不改系统文件:

| 部分 | 做什么 |
|---|---|
| [node-access](parts/001.node-access/) | 公共部分:节点读写(写完读回)、配置记忆、"出厂值"记录、`perf` 命令分发、每约 30 秒核对一次被改回去的设置 |
| [cpu-freq](parts/002.cpu-freq/) | `perf cpu …`:各簇(TB321FU 是 policy0/2/5/7)的最低/最高频率 |
| [gpu-freq](parts/003.gpu-freq/) | `perf gpu …`:Adreno 的最低/最高频率(kgsl devfreq) |
| [profiles](parts/004.profiles/) | `perf profile powersave|balanced|performance`:一键切档 |
| [thermal-readout](parts/005.thermal-readout/) | `perf temps`:CPU/GPU/外壳/电池温度,只读 |
| (单独的补丁 [perf-game-boost](../perf-game-boost/)) | 游戏模式的钩子 `perf`:名单应用前台时切性能档,离开原样恢复 |

顺序就是部分的编号;外部只要 `herald-core`。`perf-game-boost`(游戏性能联动)是单独的补丁,要 `game-mode` 和本补丁。

## 档位

| 档位 | CPU | GPU |
|---|---|---|
| powersave 省电 | 各簇最高频限到 60%(最低频出厂) | 最高频限到 60% |
| balanced 均衡 | 全部出厂值 | 出厂值 |
| performance 性能 | 各簇最低频抬到 40%(最高频出厂) | 出厂值(GPU 自己按负载升频) |

百分比 = 不超过"该簇最高档 × N%"的**最大一档**(只用 `scaling_available_frequencies` 里的真实档位)。要别的比例就用 `perf cpu set <簇号|all> <min|max> <N%|kHz|stock>`,手动设过之后档位显示 `custom`。

```bash
heraldctl perf profile powersave
heraldctl perf cpu set all max 70%
heraldctl perf cpu set 7 max 2000000
heraldctl perf gpu set max 600MHz
heraldctl perf temps
heraldctl perf cpu reset              # 全部回出厂值
```

## 做了什么、没做什么

- **做**:只写 `scaling_min_freq` / `scaling_max_freq`(以及 GPU 的 `devfreq/min_freq` / `max_freq`)。这是用户态的频率上下限,和内核、温控各自的限制取交集,所以**温控照常限频,这里不绕过它**。写完读回,内核夹成别的档位会照实报 `readback`。
- **出厂值**:每次开机第一次要改某个节点之前,先读它的当前值记下来(`$STATE/perf.stock`,带开机 id,换了开机自动作废),`stock` / `balanced` / `reset` 写回的就是这个值,而不是 `cpuinfo` 的硬件极限——因为开机脚本可能已经把 `scaling_min_freq` 设成别的值了。
- **记忆**:设过的值存 `$STATE/perf.conf`,重启后第一次空闲(开机后约 5 秒)重新套用;之后每约 30 秒核对一次,被性能 HAL(`perf2-hal`、联想 `performance` 服务)改回去就再写一遍。
- **不做**:不碰调速器(WALT)、温控、电压、`sched_boost`、核心上下线、内存/IO 调度。

## 游戏联动

装了 `perf-game-boost` 之后,`game add <包名>`(不写钩子名 = 所有钩子)也会在进游戏时切性能档,离开时把**进入前的设置原样恢复**(包括手动调过的 custom 和档位名)。只想锁定/勿扰就 `game add <包名> lock dnd`。`game perfprofile <performance|powersave|balanced>` 改进游戏用的档位。

## 没在真机上核对(第一次上机请按下面顺序)

1. `heraldctl perf cpu status`:四个簇的 `avail`、`min`、`max` 是不是合理;`governor` 应是 walt。
2. `heraldctl perf profile powersave` 后看 `policyN_max` 变没变;跑一会儿再看(性能 HAL 或温控有没有改回去,后端 30 秒内应该重新套用,`heraldctl` 日志里有"被改回去了,重新套用")。
3. GPU:`heraldctl perf gpu status` 看 `avail` 是不是 Hz 的列表;节点名按 Adreno 的 devfreq 惯例写的(`/sys/class/kgsl/kgsl-3d0/devfreq/{min,max,cur}_freq`、`available_frequencies`),这台没验证过。没有这个节点时 `gpu` 命令返回 err,档位只调 CPU。
4. `performance` 档会让 CPU 常驻在不低的频率,**耗电和发热明显增加**,温控照样会降频;不建议长期开着。
5. 实际体验差异(跑分、掉帧、续航)没测过,不要把百分比当结论,按需要调。

测试脚本:`toolkit/test-perf-plugins.sh`(假的 cpufreq/kgsl/thermal 树,含游戏联动)。
