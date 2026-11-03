# game-mode/foreground-trigger — 游戏名单与前台触发

## 做什么

维护"游戏名单",盯前台应用;进入名单里的应用时依次调各个钩子模块的 `enter`,离开时倒序调 `exit`。本身不锁、不开勿扰——那是 `game-mode/kiosk-lock`、`game-mode/auto-dnd` 这些钩子做的。整体说明、用法、退出途径、没核对的项见 [`../README.md`](../../README.md)。

命令:`game add <包名> [钩子…]`、`remove`、`list`、`on`、`off`、`release`、`debounce <秒>`、`status`。

## 钩子约定(写新钩子模块看这里)

把自己的名字追加到 `GAME_HOOKS`(不要重置它,插件按字母序加载),再定义:

| 函数 | 何时调 |
|---|---|
| `heraldp_game_enter_<名字> <包名>` | 进入名单应用;返回 0 才记入"本次生效的钩子" |
| `heraldp_game_exit_<名字>` | 离开/解除/关总开关/后台进程退出 |
| `heraldp_game_boot_<名字>` | (可选)后台进程启动:收拾上次异常中断留下的东西 |
| `heraldp_game_watch_<名字>` | (可选)常驻监听,放后台跑,可以往 `$W/game_release` 放标记触发解除 |
| `heraldp_game_status_<名字>` | (可选)往 `game status` 加几行 |
| `heraldp_game_sub_<子命令>` | (可选)给 `game` 加子命令 |

钩子里要改系统(settings/cmd/dumpsys)用 `herald_game_sysq`,配置用 `herald_game_cget/cset`(`$STATE/game.conf`)。**钩子只会在后台进程里被调**,不要在命令处理里调系统命令(会和后台进程抢临时文件)。

## 实现要点

- 配置 `$STATE/game.conf`:`enabled`、`app.<包名>=*|钩子,钩子`、`debounce`、各钩子自己的键;生效状态 `$STATE/game.state`(`active=` `hooks=` `since=`),有这个文件 = 正在生效。
- 后台进程由 `HERALDP_IDLE`(每 5 秒)和 `game add/on` 拉起,没有名单或总开关关了就自己退出;pid 在 `$W/game.pid`。broker 重启时先杀掉上一个后台进程(它会先跑 exit 钩子)。
- 前台为空(拿不到)时不动;`game release` 之后到离开那个应用之前不再重新进入。
- 弹窗/权限页让前台短暂变成别的包:V84 起默认 `debounce`=0(离开立刻恢复),权限弹窗/安装器/系统界面这类一闪而过的前台直接忽略;要更保守可 `game debounce <秒>`;直接从一个名单应用切到另一个则立刻先退后进。

## 依赖

`require_mod required/general/herald-core`。只装两个脚本:`plugins/game-core.sh`、`heraldctl.d/game.sh`。
