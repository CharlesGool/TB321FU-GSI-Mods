# game-mode/auto-dnd — 进入开勿扰,离开恢复原值

## 做什么

游戏模式的钩子 `dnd`:

| 进入时 | 做什么 | 离开时 |
|---|---|---|
| 勿扰**已经开着**(`zen_mode` 1/2/3,含定时规则开的) | **什么都不改**,也不记任何东西 | 自然保持勿扰 |
| 勿扰关着(`zen_mode` = 0) | 开 `dnd.mode`(默认 `priority` = 仅允许优先打扰,闹钟照响),记下 原值=0、我设的值 | 当前值还是我设的 → 恢复成 0;期间被别人改过 → **不动** |
| 读不到 `zen_mode` | 不改 | — |

命令:`game dndmode <priority|none|alarms>`。

## 原理

先 `cmd notification set_dnd <priority|none|alarms|off>`,再读 `settings get global zen_mode` 核对;不对再 `settings put global zen_mode`,仍不对就记 blog 并放弃(不会报成功)。状态记在 `$STATE/game-dnd.state`(`orig=` `set=`),后台进程重启/整机重启后靠它补上恢复,所以不会把勿扰留在开着。

## 依赖

`require_mod required/general/herald-core`、`require_mod game-mode/foreground-trigger`。
