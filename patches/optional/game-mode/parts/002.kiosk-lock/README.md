# game-mode/kiosk-lock — 锁住退出途径

## 做什么

游戏模式的钩子 `lock`:名单应用在前台时,禁用导航(主页/最近任务/助手手势)、下拉通知栏、快捷设置、顶部通知弹出;离开时恢复。退出途径和整体说明见 [`../README.md`](../../README.md)。

命令:`game flags <flag…|default>`(默认 `search home recents notification-peek statusbar-expansion notification-shade quick-settings`)、`game combo <UD…|default>`(默认 `UDUDUD`,4~12 个,只能 U/D)。`back` 不在默认里(游戏常用返回键开菜单);需要就 `game flags … back`。

## 原理

`cmd statusbar send-disable-flag <flags>`。这是 AOSP `StatusBarShellCommand` 的命令,用一个**静态 token** 把 flag 记在 `StatusBarManagerService` 里,命令进程退出后仍有效,`none` 清除,系统重启清零。逐个 flag 追加着发,系统报 `Unrecognized` 的跳过并写 blog,其余照常生效,所以不同 Android 版本 flag 名字不全也不会整体失败;一个都没接受则不锁(不会"半锁")。

退出组合:后台常驻读 `getevent -q` 的按键(`0001 0073`=音量上,`0072`=音量下,值 `00000001` 按下),5 秒内凑齐组合就放 `$W/game_release`,核心在下一秒执行解除。只在生效期间响应。

## 注意

- 只在"名单应用在前台"时锁;游戏崩溃/退出后 3 秒自动解锁,不会把人锁在桌面上。
- **没在真机上核对**:手势导航下 `home`/`recents` 是否真能挡住上滑、`getevent` 在 broker 域里读得到音量键吗——清单见 [`../README.md`](../../README.md)。读不到按键时,组合键解除不可用,仍有 `heraldctl game release`、游戏自己退出、电源键菜单重启。

## 依赖

`require_mod required/general/herald-core`、`require_mod game-mode/foreground-trigger`。
