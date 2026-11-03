# perf/thermal-readout — 温度读数

`perf temps [all]`:从 `/sys/class/thermal/thermal_zone*/{type,temp}` 取 CPU / GPU / 外壳(skin)/ 电池的最大值,以及全机最高温和所在 zone;`all` 另外逐个列出(`zone.<type>=温度`)。温度 ≤ 0 或明显无效的 zone(如 `-274000`)忽略。只读。依赖 `perf/node-access`。
