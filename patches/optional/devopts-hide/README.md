# devopts-hide — 开发者选项隐藏

> 一个补丁(`devopts-hide`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

按 App 隐藏开发者选项 / ADB 状态。钩子和开关合起来才有用,所以是一个补丁;默认不打。

| 部分 | 做什么 | 形式 |
|---|---|---|
| [001.hook](parts/001.hook/) | 按 App 隐藏开发者选项 / ADB 状态:名单里的 App 读这几项设置时看到"关" | 改 `framework.jar`(新 dex + 四处钩子),加一个 SELinux 类型,不依赖 herald |
| [002.control](parts/002.control/) | `heraldctl hide devopts …`:开关、模式(名单/白名单)、名单增减;开机时把规则写成配置文件 | 免 root 核心插件 + init 一次性服务,依赖 `herald-core` |

计划中:应用列表按 App 隐藏(改 `services.jar`,风险高,放在 devopts 上过真机之后)。
