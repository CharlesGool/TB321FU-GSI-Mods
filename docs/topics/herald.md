# 免 root 核心(herald-core)和接入它的补丁

把原来靠 KernelSU/Magisk + Zygisk 才能做的事,改成系统自带的 init 服务:一个跑在自己 SELinux 域(`herald`)里的 root broker,加一个无特权的命令行 `heraldctl`,供前端 App 或 adb 控制。
核心**只提供基础能力和接入方式**(命令通道、配对、工具函数、插件接口),具体功能都是别的补丁接进来的插件。

| 补丁 | 做什么 | 运行时开关 |
|---|---|---|
| [herald-core](../../patches/required/general/herald-core/) | 核心:herald 域 + broker + heraldctl + 插件接口 + `bin/resetprop` | `heraldctl selftest|pair|diag|log|raw|reboot` |
| [attestation-fix](../../patches/required/general/attestation-fix/) | keymint + inject:伪造 keystore2 的认证链;指纹/keybox/RKP/安全补丁命令 | `heraldctl spoof|keybox|rkp` |
| [spoof/global-pif](../../patches/optional/spoof/global-pif/) | 全局指纹伪装(post-fs-data 用 resetprop 覆写 build 指纹) | `heraldctl spoof set|off`,默认关 |
| [spoof/app-spoof](../../patches/optional/spoof/app-spoof/) | 按 App 伪装 Build.* | `heraldctl spoofmode|spoofapps` |
| [herald-readonly-shell](../../patches/debug/herald-readonly-shell/) | `rexec`:以 root 跑白名单里的只读查看命令 | `heraldctl rexec on [分钟]|off`,默认关,到点自动关 |
| [hotspot-control/002.control](../../patches/optional/hotspot-control/parts/002.control/) | Wi-Fi 热点覆盖项读写、热点开关 | `heraldctl wifi|hotspot` |
| battery、perf、game-mode、refresh-rate、navbar-hide、statusbar-netspeed、devopts-hide、custom-font、app-backup、tango… | 各自的运行时命令 | 各自的 `heraldctl` 子命令 |

依赖关系:所有往核心接入的补丁都 `REQUIRES herald-core`(Wi-Fi 热点命令是软依赖 `WANTS`);伪装类补丁再 `REQUIRES attestation-fix`。

## 插件接口

接口(broker 插件的 `heraldp_cmd_*` / `heraldp_cmdf_*` / `HERALDP_START` / `HERALDP_IDLE` / `HERALDP_ATTACH` / `HERALDP_SELFTEST` / `HERALDP_DIAG`,heraldctl 插件的 `heraldctl_cmd_*` / `HERALDCTL_HELP`)的完整说明在 [herald-core/README.md](../../patches/required/general/herald-core/README.md)。

## 整组独立发布

引擎 keymint / inject 从 [herald-core](https://github.com/CharlesGool/herald-core) 的 `engine/` 源码编译(`make engine`)。keybox、config.toml 里的本机私密种子和 resetprop 二进制仍是**私有**的,放在 `HERALD_PAYLOAD` 里,不进仓库。

后端接口(命令、回包格式、配对认证)的文档在本仓库上一级的 `doc/herald-backend-api.md`(不在仓库里),给前端 App 开发用。
