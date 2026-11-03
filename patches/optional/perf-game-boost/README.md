# perf/game-boost — 游戏模式的性能档钩子

[`game-mode/foreground-trigger`](../game-mode/parts/001.foreground-trigger/) 的钩子 `perf`:名单应用进前台时切到 `game perfprofile` 设的档位(默认 `performance`),离开后把进入前的 CPU/GPU 设置和档位名原样恢复(进入前先写快照 `$STATE/perf-game.state`,后台进程异常退出后下次启动会自动恢复)。

注意:`game add <包名>` 不写钩子名 = 所有已装钩子,装了本模块后默认也会切性能档;只想锁定/勿扰就 `game add <包名> lock dnd`。依赖 `game-mode/foreground-trigger`、`perf/profiles`。整体说明见 [`../README.md`](../perf/README.md)。
