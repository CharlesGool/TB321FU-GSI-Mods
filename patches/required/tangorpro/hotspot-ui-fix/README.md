# hotspot-ui-fix — 热点界面修复

> 一个补丁(`hotspot-ui-fix`),内部两个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。原来是 `hotspot-settings-entry` 和 `hotspot-qs-tile` 两个补丁,都是同一件事(热点的界面入口),合成一个(2026-11-01)。

**只有 Pixel Tablet 的 GSI 才需要**:Pixel Tablet 的 overlay 把 WLAN 热点的界面入口关了(平板不显示),别的机型的 GSI 能正常显示,不用打。

| 部分 | 做什么 |
|---|---|
| [settings-entry](parts/001.settings-entry/) | 设置 → 网络和互联网 里显示"WLAN 热点"入口 |
| [qs-tile](parts/002.qs-tile/) | 下拉快捷设置里显示热点磁贴 |

两个 overlay 各自独立(目标包不同),合在一个补丁里只是因为它们修的是同一件事。热点本身的功能(国家码在必选 6ghz-fix,名称密码、6GHz)在 [hotspot-control](../tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/) 和 [hotspot-6ghz-unlock](../../../optional/hotspot-6ghz-unlock/)。
