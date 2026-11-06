# battery/bypass-charging — 旁路充电

```
heraldctl battery bypass status   旁路状态、充电器在不在、电池状态、几个节点当前值、已确认的 chg_off
heraldctl battery bypass on       接着充电器时电池不再充电,整机用充电器供电;要几秒做验证
heraldctl battery bypass off
```

## 做法

原厂的"旁路充电"(游戏助手用)是框架里的两条投票:`input_suspend` 不挂起(输入保持打开),电池充电关闭。落到 HAL 就是写 `usb/input_suspend=0` 和 `battery/charging_enable=<布尔值>`。没有单独的"旁路"节点;`battery/bypass_setting`(`setBypassLevel`)是另一回事,含义不明,这里只读出来(`node_bypass_level`)。

`charging_enable` 的极性没核对(HAL 没取反,节点又叫 enable),所以 `bypass on` 会这样做:

1. 写 `input_suspend=0`,再写 `charging_enable=<chg_off>`(第一次是 1,和 HAL 一致)。
2. 等几秒看 `battery/status`:`Not charging` = 成功;还是 `Charging` = 极性反了,换另一个值再试一次,成功就把值记进 `battery.conf` 的 `chg_off`;`Full` 等看不出的 = 回包带 `verified=no` 的说明;两个值都没用,或者状态变成 `Discharging`(输入被挂起了,整机在吃电池)= 恢复原值并报错。
3. 没接充电器:先记下,回包说明"无法验证",接上之后由守护复查。

## 安全

电量 <= 15% 拒绝开启;已开启时降到 15% 以下由守护自动关掉并去掉记忆。守护每 5 秒看一次,发现系统把 `charging_enable` 改回去了会重写。`bypass on` 会阻塞 broker 约 4~8 秒(等状态变化)。

## 输入

无。需要 `herald-core`、`battery/node-access` 在前面。
