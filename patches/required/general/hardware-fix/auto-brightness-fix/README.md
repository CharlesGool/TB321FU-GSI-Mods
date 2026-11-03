# auto-brightness-fix — 自动亮度修复

> 一个补丁(`auto-brightness-fix`),内部 4 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

GSI 的自动亮度是坏的。这个补丁把它修好:设置里有自适应亮度、手动最低档、原厂自动亮度曲线、原厂反应速度(四个静态 RRO)。

| 部分 | 做什么 |
|---|---|
| [auto-brightness](parts/001.auto-brightness/) | 设置里有"自适应亮度" |
| [min-brightness](parts/002.min-brightness/) | 手动亮度最低档 = 原厂(约 0.86 尼特) |
| [brightness-curve](parts/003.brightness-curve/) | 联想 TB321FU 原厂自动亮度曲线 |
| [brightness-debounce](parts/004.brightness-debounce/) | 自动亮度反应速度(原厂 2 秒/3 秒) |
| [display-config](parts/005.display-config/) | 原厂面板亮度配置(尼特表)放进 product,自动亮度才能降到正常的暗度 |

另见可选补丁 [brightness/hbm-unlimited](../../../../optional/brightness/hbm-unlimited/)(手动拉满 = 面板真峰值,默认不打)。
