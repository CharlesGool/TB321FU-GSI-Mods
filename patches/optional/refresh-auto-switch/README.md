# refresh-auto-switch — 按应用 / 电量自动换刷新率

## 做什么

按场景自动换刷新率,后端每约 5 秒判断一次,规格变了才写设置。优先级从高到低:

1. **前台应用规则**:`refresh app <包名> <规格>`(例:阅读软件 `30`、游戏 `90-165`、浏览器 `60`)。
2. **低电量封顶**:电量低于 N% 且没在充电时,最高不超过某个值(`refresh battery 20 60`)。封顶压在 1、3 的结果上。
3. **默认**:`refresh default <规格>`,没设就是 `auto`(系统默认)。

| 命令 | 作用 |
|---|---|
| `refresh adaptive on\|off\|status` | 开/关自动模式;`off` 会恢复系统默认;`status` 显示前台应用和当前套用的规格 |
| `refresh default <规格>` | 没有别的规则时用 |
| `refresh app <包名> <规格\|off>` | 给应用单独定;`off` 删掉规则 |
| `refresh apps` | 列出所有应用规则(`包名=规格`) |
| `refresh battery <1-99> <规格>` / `refresh battery off` | 低电量封顶 / 取消 |

规格:`auto`、一个档位 `N`(锁定),或 `A-B`(范围,`0` = 不限,如 `60-0`)。档位必须是面板支持的(`refresh modes`)。

## 原理

套用规格走 `refresh-control` 的 `herald_ref_apply`(写 `min_refresh_rate` / `peak_refresh_rate`)。前台应用取 `dumpsys window` 的 `mCurrentFocus`,拿不到(`null`)就看 `mFocusedApp`。规则存在 `/data/adb/herald/refresh.conf`,重启后保留;自动模式开着,重启后第一个 5 秒就会重新套用。

## 注意

- **为什么不是系统自己的可变刷新率**:系统(DisplayModeDirector + SurfaceFlinger 内容检测)在 `range` 范围里本来就会按内容升降;这个模块补的是"按应用/电量定范围",不是帧级调度。
- **延迟**:切应用到刷新率变化最长约 5 秒。想更灵敏要么缩短 idle 周期(影响整个后端),要么换成事件驱动(监听 `ActivityTaskManager`),这里没做。
- **手动设置会覆盖**:你在系统设置里改"流畅显示"、或 `refresh set/range/auto`,会退出自动模式(命令)或在下一次规格变化时被覆盖(设置里改)。
- 前台判断每 5 秒跑一次 `dumpsys window`,开销是一次 binder 调用,和电池插件同级。

## 没在真机上核对

`mCurrentFocus` / `mFocusedApp` 的格式按 Android 15 的常见输出写的,分屏/悬浮窗时取到的是焦点窗口。真机上先 `heraldctl refresh adaptive status` 看 `foreground=` 对不对,再设规则。

## 依赖

`require_mod required/general/herald-core`、`require_mod refresh-control`。

## 验证

```bash
toolkit/test-refresh-plugins.sh
heraldctl refresh adaptive on
heraldctl refresh app com.android.chrome 60
heraldctl refresh default 120
heraldctl refresh adaptive status        # 切到 Chrome 后约 5 秒内 applied=60
```
