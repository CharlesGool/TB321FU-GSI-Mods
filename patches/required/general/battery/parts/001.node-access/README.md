# battery/node-access — 电池命令的公共部分

## 做什么

- 给 herald broker 加 `battery <子命令> …`:按子命令名找 `heraldp_bat_sub_<名字>()`,所以各 `battery/*` 模块只管自己的子命令。
- 公共函数:节点名到路径(`herald_bat_node`)、读(`herald_bat_read`,去换行回车,保留空格)、写后读回(`herald_bat_write`,读回不同返回 2)、`battery.conf` 记忆(`herald_bat_cget/cset`)。
- 空闲调度:快档每 5 秒,慢档开机后一次、之后约每 5 分钟。各模块定义 `heraldp_bat_reapply_<名字>()`,把名字追加进 `BAT_FAST_MODS` / `BAT_SLOW_MODS`。plugins 按文件名顺序加载,所以这两个列表不在本文件里赋初值。
- heraldctl 侧:`heraldctl battery <子命令> …` 原样转发给 broker。`heraldctl help` 的"电池"一节由本模块的 `heraldctl_help_battery` 按固定顺序(info、protect、limit、bypass)调用各模块定义的 `heraldctl_help_battery_<名字>()`;heraldctl.d 里的文件按文件名顺序加载,各模块不能靠自己往 `HERALDCTL_HELP` 追加来排版。

测试时 `HERALD_BAT_SYSROOT` 可以把 `/sys` 换成假树。

## 输入

无。需要 `herald-core` 在前面。
