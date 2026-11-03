# overlay-cache — overlay 缓存自愈

保数据升级时,`/data/resource-cache` 里旧的、损坏的 idmap 会让 `idmap2d` 崩溃,对应 overlay 失效。这一组在开机时清掉我们自己 overlay 的旧 idmap。

| 模块 | 做什么 | 能不能单独关 | 运行时开关 |
|---|---|---|---|
| [idmap-reset](../../patches/optional/overlay-idmap-reset/) | 开机 `post-fs-data` 删我们 overlay 的旧 idmap(+ 给 init 删它们的 SELinux 权限) | 能。关了之后遇到坏 idmap 要 root 手动清 | 无 |

与其他模块互不依赖。
