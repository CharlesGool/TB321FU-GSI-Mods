# herald-core — 免 root 核心

## 做什么

只提供"不靠 root 工具也能让系统服务以 root 干活"的基础能力和接入方式,**自己不带任何具体功能**:

- 一个跑在自己 SELinux 域(`herald`)里的 init 服务 `herald_main`,boot_completed 后拉起 broker(`herald-start.sh`)。
- broker 的命令通道:命令行(`/system/bin/heraldctl`,无特权)和已配对前端 App,按白名单命令代执行。
- 配对:前端 App 的唯一性、设备随机密钥、uid 校验(`pair` / `unpair` / `pair_status`)。
- 基础工具:`bin/resetprop`(root 改系统属性)、Settings.Global 读写(`herald_getg/setg/delg`)、跑系统命令(`herald_sys`)、日志(`log` / `blog`)。
- **插件接口**:别的补丁往插件目录放文件,就能给 broker 和 heraldctl 加命令、加守护、加自检/诊断内容。

内置命令只有 `pair` `unpair` `pair_status` `selftest` `diag` `reboot`(heraldctl 另有 `log` `raw`)。
原来内置在这里的 keymint 引擎、指纹伪装、keybox、RKP、Wi-Fi 热点命令,现在分别是
`attestation-fix` 和可选 `hotspot-control` 的 `002.control` 部分——它们和其他功能补丁(电池、性能、游戏…)地位相同,都是接入核心的插件。

> 名字沿革:原叫 `omk-core`(最初参考 Oh My Keymint 的做法),核心现在已经和它无关,改叫 `herald-core`(herald = 传令官:无特权的前端把请求交给它,它在受控范围内代为执行)。
> 设备上的运行时标识也一并改成 herald(`herald` 域、`herald_exec` 标签、`/system/etc/herald_payload`、`/data/local/tmp/herald`、`heraldctl`、`herald_main` 服务),
> 前端 App 要按新名字对接,接口文档见项目 `doc/herald-backend-api.md`(前端的设置键、命令名、路径都已改成 herald)。keymint/inject 引擎也已由 `herald-core` 项目从上游源码重编,写死的路径同步改成 `/data/misc/keystore/herald`、`/data/adb/herald`,不再有 omk 字样。

## 插件接口

### broker 插件:`/system/etc/herald_payload/plugins/<名字>.sh`

broker 启动时按**文件名顺序**把它们 `source` 进自己的 shell(同一个 shell,能用 `$W` `$STATE` `$PAYDIR` `herald_getg` `herald_sys` `log` `blog`…)。
有先后依赖的用数字前缀:`00-attestation.sh` 先于 `app-spoof.sh`(后者顶层要用前者定义的 `CFG`)。

| 约定 | 作用 |
|---|---|
| `heraldp_cmd_<命令>()` | 加一条命令。`$1` = 命令后面的整串,**标准输出**就是回包,第一行以 `ok` / `err` 开头。命令名只许小写字母、数字、下划线 |
| `heraldp_cmdf_<命令>()` | 同上,但回包由函数自己写进 `"$resp"`(要追加、要 `cp` 文件、要先写后改的用这个) |
| `HERALDP_START` | 追加函数名:所有插件加载完后各调一次(起守护、做一次性初始化) |
| `HERALDP_IDLE` | 追加函数名:主循环空闲时每 5 秒调一次 |
| `HERALDP_ATTACH` | 追加 `"<命令>:<文件名>:<raw\|b64>"`:这条命令的请求第 2 行起是附带数据。命令行通道搬进 `$W/<文件名>`(`b64` = 去掉换行);前端 App 通道从自己 `files/<文件名>` 取 |
| `HERALDP_SELFTEST` / `HERALDP_DIAG` | 追加函数名:`selftest` / `diag` 时各调一次,标准输出并进回包 |

### heraldctl 插件:`/system/etc/heraldctl.d/<名字>.sh`

heraldctl 启动时 `source`。可以用 `send "<broker 命令行>" [附带数据文件]`、`die`、`$TMPF`、`$D`。

| 约定 | 作用 |
|---|---|
| `heraldctl_cmd_<命令>()` | 加一条 heraldctl 子命令(参数是命令后面的) |
| `HERALDCTL_HELP="${HERALDCTL_HELP:-} <函数名>"` | 帮助函数,`heraldctl help` 时输出 |

### 其他

- 要往 payload 目录放东西的补丁,文件标签用 `u:object_r:herald_exec:s0`(`/system/etc/herald_payload` 整个目录都是)。
- 要自己的 SELinux 规则就 `cil_append` 一份 CIL(核心的类型 `herald` / `herald_exec` 已经声明)。
- 核心装好 `bin/resetprop`,别的补丁直接用 `/system/etc/herald_payload/bin/resetprop`。

## 原理(大致)

- broker(`herald-start.sh`):boot_completed 后在 herald 域起,轮询请求文件,按白名单代执行命令。命令行通道 `/data/local/tmp/herald`(shell 可写,**只放 req/resp**,按 id 区分);App 通道要先 `heraldctl pair <包名>` 配对(设备随机密钥 + uid 校验)。回包先写临时文件再 rename,避免读到半截。
- broker 日志放 root 私有的 `$STATE=/data/adb/herald/broker.log`(不放 shell 可写的通道目录,免被符号链接劫持 root 写入),由 `heraldctl log` 经 broker 读回。工作目录 `$W=/data/local/tmp/herald/.work` 仍留在通道区(root 0700,shell 进不去):回包 resp 在这里生成、带 `shell_data_file` 标签,rename 给 heraldctl(shell 域)才读得到——放到 `/data/adb` 会因 SELinux 标签不对让回包读不出来(V1.2 真机实测)。
- 自适应轮询:刚处理过请求后约 3 秒内每 0.1 秒看一次(连续操作几乎不等),空闲回落到每 1 秒;`HERALDP_IDLE` 钩子按墙上时间约每 5 秒触发,与轮询快慢无关。
- cmd/dumpsys 的输出必须落文件,不能走管道(binder 传 fd 时接收方 system_server 要对 herald 的 fd 做检查,V62 加了 `herald:fd use` 放行)。
- sepolicy:herald 域 permissive(等价设备上 KSU 的 blanket);herald 域归入 `netdomain`(V33:否则任何网络 socket 都报 EMSGSIZE)。keystore 域侧的放行不在这里,属于 attestation-fix。

## 改动清单

- `etc/herald_payload/`:`herald-start.sh`、`bin/resetprop`、`plugins/`(空,别的补丁往里装)。全目录 `herald_exec` 标签。
- `etc/init/init.herald.rc`、`bin/heraldctl`、`etc/heraldctl.d/`(空)。
- `plat_file_contexts` 加 herald_payload 条目,`plat_sepolicy.cil` 追加 herald 域。

## 输入(device.conf)

| 变量 | 说明 |
|---|---|
| `HERALD_PAYLOAD` | 私有 payload 目录。核心只用其中的 `bin/resetprop`;`bin/{keymint,inject}` 和 `seed/*` 是 attestation-fix 的 |

## 依赖和顺序

无依赖。别的补丁依赖它(`REQUIRES`):attestation-fix、battery、perf、game-mode、refresh-rate、navbar-hide、tango、statusbar-netspeed、devopts-hide、custom-font、app-backup、herald-readonly-shell…
可选的 `hotspot-control` 对它是软依赖(`WANTS`):没选核心时热点自定义的 Settings 键照常打,只是没有 `heraldctl wifi|hotspot`。

## 换底包注意

和底包无关(shell 脚本 + 一个 resetprop ELF),换 GSI 不用动。sepolicy 追加的 herald 域由构建框架清零 sha256 强制 init 重编。

## 踩过的坑

- V34:回包"文件存在"当"写完"信号,读到空串 → 写临时文件再 rename。
- V62:cmd/dumpsys 报 `Failed transaction (2147483646)`,真因是 system_server 缺 `herald:fd use`。
- V64:heraldctl 每次请求用自己的 id(多个 heraldctl 同时跑或上一条被打断不再串回包);超时分"没被取走"/"还在执行"两种。
- V75:heraldctl 的回包直接从文件输出,不放进变量再 printf(mksh 没有内建 printf,回包一大就 `Argument list too long`)。
- V85/V86:不用 `trap EXIT`(mksh 设了 EXIT trap 后,变量未定义这类错会让整个脚本退出);shell 自己的报错写 `/metadata/herald_log/herald-start.err`。

## 验证

```bash
adb shell heraldctl selftest          # 身份/SELinux/读写设置/配对 + 各插件的自检都绿
adb shell heraldctl diag
adb shell heraldctl pair
```

仓库里的回归:`toolkit/tests/test-herald-protocol.sh`(在模拟环境里跑真正的 broker 和 heraldctl,可对比旧版回包逐字节相同)、
`test-herald-start-full.sh --repo`(mksh 下整个开机路径不退出、不报错)、`test-herald-start-prefix.sh`。
