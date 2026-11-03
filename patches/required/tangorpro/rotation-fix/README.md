# rotation-fix

> 一个补丁(`rotation-fix`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

屏幕方向修复:只能横屏的应用画面不再倒过来;去掉 Pixel Tablet 底座的方向设置(两个静态 RRO)。

| 部分 | 做什么 |
|---|---|
| [rotation-reverse-fix](parts/001.rotation-reverse-fix/) | 修横屏应用画面倒过来 |
| [dock-rotation-fix](parts/002.dock-rotation-fix/) | 去掉 Pixel Tablet 底座的方向设置 |
