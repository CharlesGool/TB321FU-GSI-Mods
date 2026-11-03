# game — 游戏模式

> 一个补丁(`game-mode`),内部 3 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`game-mode`),内部 3 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

指定一批应用,它们在前台时:**退不出来**(导航、最近任务、下拉通知栏、快捷设置都不响应)、**自动开勿扰**;离开后全部恢复。三个模块,都是 免 root 核心插件,没有 RRO 也不改系统文件:

| 部分 | 做什么 | 关掉它会怎样 |
|---|---|---|
| [foreground-trigger](parts/001.foreground-trigger/) | 名单 + 前台应用监听 + 进入/离开时触发钩子;`heraldctl game …` | 整个游戏模式没了(另外两个依赖它) |
| [kiosk-lock](parts/002.kiosk-lock/) | 钩子 `lock`:禁用导航/最近任务/助手手势/通知栏/快捷设置;音量键组合解除 | 只剩自动勿扰 |
| [auto-dnd](parts/003.auto-dnd/) | 钩子 `dnd`:进入开勿扰,离开恢复原值(本来就是勿扰就一律不动) | 只剩锁定 |

顺序:`herald-core`、`game-mode/foreground-trigger`、再是另外两个(随意顺序)。每个应用可以只用一部分钩子:`heraldctl game add com.xxx dnd`。

## 怎么用

```bash
heraldctl game add com.tencent.tmgp.sgame          # 加入名单(锁定 + 勿扰都用)
heraldctl game add com.android.chrome dnd          # 只开勿扰,不锁
heraldctl game list
heraldctl game status                              # 前台应用、是否生效、锁了哪些 flag、勿扰记的原值
heraldctl game release                             # 立刻解除本次(应用还在前台也不再锁;离开再进才重新生效)
heraldctl game combo UDUDUD                        # 退出的音量键组合(U=音量上 D=音量下),5 秒内按完
heraldctl game dndmode priority|none|alarms        # 开哪种勿扰
heraldctl game off                                 # 总开关
```

## 退出途径(应用里按不出来)

1. **音量键组合**(默认 音量上、下、上、下、上、下,5 秒内按完)——后台常驻读 `getevent`;
2. `heraldctl game release`(adb)或前端发 `game release`;
3. 应用自己退出/崩溃:前台换了,3 秒(`game debounce`)后自动解锁、恢复勿扰;
4. 电源键长按菜单重启:禁用 flag 重启后清零。

后台进程里**所有改动都有"回收"路径**:`game off`、名单清空、后台进程被杀(`TERM`)、broker 重启,都会先执行 exit 钩子再退出;万一整机掉电重启,flag 本来就清零,勿扰则靠 `$STATE/game-dnd.state` 在下次后台进程启动时补恢复。

## 原理

- **前台应用**:`logcat -b events` 的 `wm_set_resumed_activity` / `wm_focused_app`(事件驱动,没有轮询);后台进程每 5 秒再用 `dumpsys window` 的 `mCurrentFocus` 对一次(防监听挂掉)。弹窗型 Activity(权限弹窗)会让前台短暂变成别的包,所以离开要持续 3 秒才算。
- **锁定**:`cmd statusbar send-disable-flag <flags>`(AOSP `StatusBarShellCommand`,静态 token,`none` 清除)。
- **勿扰**:`cmd notification set_dnd <priority|none|alarms|off>`,读回 `settings get global zen_mode` 核对,不行就直接 `settings put global zen_mode`。
- **架构**:一个后台子进程做所有"改系统"的动作,命令处理(主 shell)只改配置文件和放"解除"标记,两边不会同时用同一个临时文件。钩子见 `foreground-trigger/files/game-core.sh` 开头的约定,以后加"进入游戏时压低后台、强制刷新率、关自动亮度……"都是再加一个钩子模块。

## 没在真机上核对(第一次上机请按下面顺序)

1. `cmd statusbar help` 里有没有 `send-disable-flag`,以及 flag 名字(`search home recents notification-peek statusbar-expansion notification-shade quick-settings` 是按 AOSP 写的;系统不认的会被**跳过并记 blog**,其余照常生效,`heraldctl game status` 的 `lock_applied=` 能看到最终生效的)。
2. 手势导航下 `home`/`recents` flag 能不能真的挡住上滑回桌面(PixelOS 的 Launcher3 是否听 SystemUI 的 disable 状态)。
3. `logcat -b events` 里有没有 `wm_set_resumed_activity`(没有也行,5 秒轮询兜底,只是慢);`heraldctl game status` 的 `foreground=` 随切应用变化。
4. `getevent` 能不能读到音量键(权限、设备),组合键能不能解除。
5. 勿扰:进入后 `settings get global zen_mode` = 1,退出后 = 0;事先手动开勿扰再进入,退出后应保持勿扰。
6. 兜底:锁住后任何情况拔不出来时,电源键长按 → 重启一定能恢复。

测试脚本:`toolkit/test-game-plugins.sh`(桩 settings/cmd/dumpsys、假 logcat/getevent,含一个真起后台进程的冒烟)。
