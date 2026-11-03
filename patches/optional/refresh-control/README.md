# refresh-control — 刷新率控制

## 做什么

给 免 root 核心加 `refresh` 命令(`heraldctl refresh …`),让前端或命令行能锁定刷新率,或限定一个范围让系统在范围里自己挑。面板支持 30 / 60 / 90 / 120 / 144 / 165 Hz。

| 命令 | 作用 |
|---|---|
| `refresh status` | 当前实际刷新率、`min` / `peak` 设置、面板支持的档位、是不是自动模式 |
| `refresh modes` | 面板支持的档位(从 `dumpsys display` 读,不写死) |
| `refresh set <Hz>` | 锁定到某一档(`min` 和 `peak` 都写这个值) |
| `refresh range <最小> <最大>` | 限定范围,`0` = 不限(例:`range 60 120`;`range 0 90` 只封顶;`range 60 0` 只设下限) |
| `refresh auto` | 两个键都删掉,恢复系统默认 |

## 原理

系统的 `DisplayModeDirector` 把 `Settings.System` 里的 `min_refresh_rate` / `peak_refresh_rate` 当"用户设置"那一票读(设置里"流畅显示"开关写的也是 `peak_refresh_rate`),所以改这两个键就等于用户在设置里选了。不用改任何系统文件,也不用 overlay。

- 写完会读回核对,写不进就报错;档位不在面板支持的列表里直接拒绝(系统会悄悄忽略不支持的值,用户会以为生效了)。
- `dumpsys display` 报的是 `120.00001`、`60.000004` 这种浮点,四舍五入成整数后比较。
- 手动 `set` / `range` / `auto` 会退出 `optional/refresh-auto-switch` 的自动模式,免得下一个 5 秒被它改回去。
- 设置本身由系统保存,重启后还在。

## 没在真机上核对

- 系统会不会因为别的投票(省电模式、低电量、`vendor.display.enable_optimize_refresh`、游戏降帧)压过用户设置,`status` 的 `active` 可以看到最后实际跑的值。
- 内容检测(SurfaceFlinger)已经开着,`range` 的范围里系统会按内容升降;"锁定"是 `min == peak`。
- 面板有没有真正的 LTPO 级差,取决于固件,和这个模块无关。

## 依赖

`require_mod required/general/herald-core`。`optional/refresh-auto-switch` 要求它排在前面。不碰分区内容以外的任何东西,只装两个插件脚本:`/system/etc/herald_payload/plugins/refresh-rate.sh`、`/system/etc/heraldctl.d/refresh-rate.sh`。

## 验证

```bash
toolkit/test-refresh-plugins.sh                 # 单元测试(桩 settings/dumpsys,dash 和 busybox sh)
heraldctl refresh status
heraldctl refresh set 60                           # 看实际刷新率;状态栏/开发者选项里的刷新率显示可确认
heraldctl refresh auto
```

自适应刷新率修复(系统层的静止降档/触摸升档)是必须打的 [hardware-fix/adaptive-refresh-fix](../../required/general/hardware-fix/adaptive-refresh-fix/);本补丁只是手动锁定/限定刷新率的命令,可选。设置里"流畅显示"的档位见 [smooth-display](../smooth-display/)。
