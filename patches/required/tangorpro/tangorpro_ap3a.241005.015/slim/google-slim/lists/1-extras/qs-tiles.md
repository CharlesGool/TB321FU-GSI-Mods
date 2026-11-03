# 清单 · qs-tiles(下拉栏磁贴)

精简掉某些应用后,下拉栏里依赖它们的磁贴就成了摆设。`qs-tiles.tiles` 一行一个 `磁贴名 依赖路径`;精简完这一级及更低级之后,依赖路径不在了,就用静态 RRO 覆盖 SystemUI 的 `quick_settings_tiles_default`,把磁贴从**默认列表**(`quick_settings_tiles_default`,下拉栏默认显示的)和**内置总表**(`quick_settings_tiles_stock`,编辑页"可添加"区的来源)里都去掉。路径还在就不动。

| 磁贴 | 依赖 | 说明 |
|---|---|---|
| `controls`(设备控制) | `GoogleHomePrebuilt` | 控制器提供者是 Google Home,精简后磁贴没有东西可控 |
| `wallet`(钱包) | `GoogleWallet` | 这版底包没有 Google 钱包应用,磁贴没用,总是去掉 |

`cast`(投放)保留:它走 Google Play 服务的 Cast,Play 服务没删,磁贴能用。

两张表的原值在上一级目录的 `tiles.default`、`tiles.stock`(这版底包 SystemUITitan 带的),换底包要对着更新。加新磁贴:写到被它依赖的应用所在那一级的 `*.tiles` 里。

只影响新用户和"重置磁贴"后的默认列表;用户自己排过的不受影响。清数据刷机后生效。
