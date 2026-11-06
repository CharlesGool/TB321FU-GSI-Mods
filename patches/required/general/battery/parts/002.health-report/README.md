# battery/health-report — 电池寿命查看

`heraldctl battery info`:只读,回包第一行 `ok battery info`,后面每行 `键=值`,读不到的键不输出。

| 键 | 来源 |
|---|---|
| `level` `status` `health` | `power_supply/battery/capacity` `status` `health` |
| `temp_c` `voltage_mv` `current_ma` | `temp`(0.1℃)、`voltage_now`(µV)、`current_now`(µA),充电时电流为负 |
| `time_to_full_s` `time_to_empty_s` | `battery/time_to_full_now` `time_to_empty_now` |
| `usb_online` `wireless_online` | `usb/online` `wireless/online` |
| `cell1_*_raw` `cell2_*_raw` | `qcom-battery/fg1_*`、`fg2_*`(cycle_count、soh、temp、voltage、current、activate_date、produce_date),**原样输出,单位没核对** |
| `cell1_manufacturer` `cell2_manufacturer` | `qcom-battery/battery{1,2}_manufacturer` |
| `cells` `cycle_max` | 有数据的电芯数;两颗里较大的循环次数 |
| `node_protection` `node_limit` `node_recharge` `node_bypass` `node_chg_enable` `node_input_susp` | 其他电池节点的当前原始值,真机核对用 |

这台是双电芯(原厂 HAL 有 fg1 和 fg2 两套)。先看 `cell*_raw` 的数值范围再决定怎么合成给用户看的"电池健康度"。

## 输入

无。需要 `herald-core` 和 `battery/node-access` 在前面。
