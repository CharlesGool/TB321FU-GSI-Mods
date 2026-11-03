# net — 网络

> 一个补丁(`statusbar-netspeed`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`statusbar-netspeed`),内部 2 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

| 部分 | 做什么 | 形式 |
|---|---|---|
| [statusbar-speed](parts/001.display/) | 状态栏网速显示:framework 里加类,运行时把 TextView 插进真实状态栏 | 改 `framework.jar`(新 dex + 一处钩子),不改 SystemUI 的 APK,不依赖 herald |
| [speed-control](parts/002.control/) | `heraldctl netspeed …`:开关、位置、模式、单位 | 免 root 核心插件,依赖 `herald-core` |
