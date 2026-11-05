# navbar-hide/control — 导航栏隐藏的控制

## 做什么

给 OMK 控制后端加 `navbar` 命令,开关三个导航栏 overlay:

```
heraldctl navbar hide     隐藏
heraldctl navbar show     恢复
heraldctl navbar status   当前状态、导航模式、底部是任务栏还是导航栏
```

## 原理

靠 [herald-core](../../../../required/general/herald-core/) 的插件机制:

- `plugins/navbar.sh`(broker 插件):`heraldp_cmd_navbar` 处理命令;`herald_nav_guard` 挂进 `HERALDP_IDLE`,主循环空闲时每 5 秒跑一次。
- `heraldctl.d/navbar.sh`(heraldctl 插件):加 `navbar` 子命令和帮助。

`hide`:`cmd overlay enable --user 0` 三个包 + `set-priority highest`,杀启动器让它重读资源。`show` 相反。

**手机模式(显示大小为"大",最小宽度 < 600dp,底部是 SystemUI 的 NavigationBar0)不再杀 SystemUI**:
SystemUI 只在创建导航栏窗口时读一次 inset 和手柄颜色,以前只好杀进程让它重建。现在用 `cmd overlay enable-exclusive --category`
把导航模式 overlay(`…systemui.navbar.threebutton` 再 `…gestural`)各启用一次——这会让系统广播配置变化,SystemUI 在自己进程里
销毁并重建导航栏窗口,效果等同重启 SystemUI 的导航栏部分,但状态栏、通知、最近任务都不动。
重建后读 `dumpsys window` 里 `type=navigationBars` 的 frame 面积来校验(隐藏后应为 0,恢复后应非 0),最多等 4 秒;
**没生效或读不出来就回落到杀 SystemUI**(行为和以前一样,不会更差)。结果写进 `heraldctl log`,例如
`navbar: enable 后重启 launcher (SystemUI 没重启:导航栏已重建)(bar=navbar 手机模式=0 sw=533dp)`(手机模式=0 是手机、1 是平板、2 读不到),
回落时是 `重启 launcher systemui(轻量重建没生效,inset=…,已回落重启)`。
重建期间有 `navbar_busy` 标记,守护 `herald_nav_guard` 看到就跳过(超过 1 分钟的残留标记忽略),避免两边同时动手。
平板模式本来就只杀启动器(任务栏在启动器进程里)。命令的回包格式不变。三个全开失败时不保存意愿、不重启(否则守护每 5 秒重试一次、反复重启启动器)。

**连着多次 hide/show 的稳定性(真机反馈:频繁切换后导航栏失灵,要手动重启导航模式/UI 才恢复)**:
手机模式下不再同时杀启动器(它没有任务栏,杀了只会和导航模式切换抢着重建);切完确认 `navigation_mode` 回到 2(手势),没回就补切,补不回来写日志;每次切完再等 2 秒才放行下一条命令。这是按代码推测的修法,**没有真机验证**;再出现时看 `heraldctl log` 里 `navbar:` 的行。

**只在手势导航下生效**:三键/两键导航时按钮还得占位,所以守护按 `navigation_mode` 自动撤(切三键时恢复显示)或自动开(切回手势再隐藏)。用户意愿记在 `/data/adb/herald/navbar_hide`,重启保留。

底部是谁画的,看 `dumpsys window windows` 里有没有 `NavigationBar0`(手机模式)或 `Taskbar`(平板模式)。

## 改动清单

- `etc/herald_payload/plugins/navbar.sh`(0644 `herald_exec`)、`etc/heraldctl.d/navbar.sh`(0644 `system_file`)。

## 输入

无。

## 依赖和顺序

`require_mod required/general/herald-core`(控制后端,这是互不依赖规则的唯一例外)。控制的对象是 `navbar/overlay-*` 三个模块,但构建上不依赖它们:没装的 overlay 在 `hide` 时报 `fail`,装了的照样生效。

## 换底包注意

`cmd overlay`、`settings get secure navigation_mode` 都是 Android 公共接口。`navbar.sh` 依赖 herald-start.sh 里的 `herald_sys`、`blog`、`$W`、`$STATE`,core 改了这些要同步。

## 踩过的坑

- V65:overlay 没注册(见 overlay-* 的 README)。
- V65:`hide` 全失败时 pref 仍被改成 hide(V66 修:全失败不保存)。
- 守护重试环:失败后 APPLIED 标记没设,守护每 5 秒重新 enable 并杀启动器。现在失败也设/撤标记。

## 验证

模拟测试(假的 cmd/dumpsys/wm)覆盖 5 种情况:手机隐藏/显示重建有效→不杀 SystemUI;重建无效→回落杀;读不到 inset→回落杀;平板模式→只杀启动器。**真机未验证**:`enable-exclusive` 是否真让 SystemUI 重建导航栏、重建后 frame 的读数,都要在真机上看 `heraldctl log`。

见组 README 和各 overlay 的验证。真机:隐藏后上滑回桌面/多任务、侧滑返回都在;平板模式和手机模式(`wm density 480`)两种都试;切三键导航自动恢复,切回手势自动隐藏;重启后保留。
