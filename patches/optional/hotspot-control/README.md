# hotspot-control — 热点控制(可选)

> 一个补丁(`hotspot-control`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

GSI 上热点的名称、密码、频段这些只能进系统设置页改,前端或后端没法程序化地改。这个补丁解决这件事。
国家码和 6GHz 频段修复不在这里,是必选的 [6ghz-fix](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/)。

| 部分 | 做什么 | 运行时开关 |
|---|---|---|
| [001.hotspot-custom](parts/001.hotspot-custom/) | 热点自定义:`herald_ap_*` 覆盖热点名称、密码、加密、频段等 | `herald_ap_*` |
| [002.control](parts/002.control/) | 接入 [herald-core](../../required/general/herald-core/):`heraldctl wifi …` / `heraldctl hotspot …` 命令(覆盖项读写、热点开关、读系统热点设置,白名单里也放行 `herald_6g_*`);没选核心时跳过 | `heraldctl wifi|hotspot` |

自定义部分只"登记"smali 补丁,打包重签在必选的 [wifi-apex-assemble](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/),选了本补丁会自动带上它。
