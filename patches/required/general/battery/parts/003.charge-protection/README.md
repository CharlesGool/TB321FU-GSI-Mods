# battery/charge-protection — 电池保护(长期插电保护)

```
heraldctl battery protect status        raw、是否开启、min/max、记住的设置
heraldctl battery protect on [min max]  默认 75 80;要求 20 <= min < max <= 100
heraldctl battery protect off
```

写 `power_supply/battery/protection_setting`:开 = `100000 + min*1000 + max`,关 = `95100`(原厂 `setBatteryProtectedLevel` 的做法)。回包里的 `readback=` 是写完读回的值。设置记在 `battery.conf`,守护发现被改回去会重写;`protect off` 清掉记忆。

注意:这和 `battery/charge-limit` 是两个节点(`protection_setting` 和 `protection_setting_eu`),原厂也分开。两个同时开时内核怎么取舍没核对。

## 输入

无。需要 `herald-core`、`battery/node-access` 在前面。
