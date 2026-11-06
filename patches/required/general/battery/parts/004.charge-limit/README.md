# battery/charge-limit — 充电上限

```
heraldctl battery limit status
heraldctl battery limit <20-100> [回充比例]   到上限停充,低于 上限x回充比例% 才重新充;回充比例默认 95
heraldctl battery limit off                   = 上限 100
```

写 `battery/protection_setting_eu` 和 `battery/recharge_setting`。原厂 `setMaxBatteryChargingLevel(P)` 写 `100000 + 95*P*10 + P`(95 是回充比例),只在 P 是 20 的倍数时才是整齐的"下限*1000+上限"。这里直接按 `100000 + 下限*1000 + 上限` 写,下限 = 上限 x 回充比例/100(整数除),80% 得 `176080`、100% 得 `195100`,和原厂一致;其他上限(比如 85)按这个整齐写法,**内核是否按"下限*1000+上限"解读没核对**,先用 80 和 100 验证。

设置记在 `battery.conf`(`limit=上限:回充比例`),守护发现被改回去会重写。

## 输入

无。需要 `herald-core`、`battery/node-access` 在前面。
