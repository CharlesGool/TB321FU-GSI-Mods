# battery — 电池寿命、保护、充电上限、旁路充电

> 一个补丁(`battery`),内部 5 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`battery`),内部 5 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

TB321FU 的电池相关功能。原厂 ZUI 靠 `ZuiBatteryManagerService`(在 `services.jar` 里)加 vendor 里的 `vendor.lenovo.hardware.battery-service`(AIDL HAL,root)实现;GSI 的 framework 里没有前者,HAL 还在。这里的做法是让 herald 控制后端的 root broker **直接读写 HAL 用的那批 sysfs 节点**,命令是 `heraldctl battery …`。

| 部分 | 命令 | 做什么 |
|---|---|---|
| [node-access](parts/001.node-access/) | `battery <子命令>` 的分发、设置记忆、空闲时核对 | 公共部分,其余部分都靠它 |
| [health-report](parts/002.health-report/) | `battery info` | 只读:电量、温度、两颗电芯的循环次数/健康度/日期/厂商,以及各节点当前原始值 |
| [charge-protection](parts/003.charge-protection/) | `battery protect status\|on [min max]\|off` | 长期插电保护:电量保持在区间内 |
| [charge-limit](parts/004.charge-limit/) | `battery limit status\|<20-100> [回充比例]\|off` | 充电上限:到上限停充,低于 上限x回充比例 才重新充 |
| [bypass-charging](parts/005.bypass-charging/) | `battery bypass status\|on\|off` | 旁路充电:接着充电器时电池不充电,整机用充电器供电 |

都靠 `herald-core` 的插件机制,所以必须排在 `herald-core` 后面;后四个还要 `battery/node-access` 在前面。

## 节点和取值(来自原厂固件的反编译)

证据:原厂 `vendor/bin/hw/vendor.lenovo.hardware.battery-service`(`Battery.cpp`,函数名从二进制自带的符号表读出)和原厂 `services.jar` 里的 `com.lenovo.lgsi.server.battery.ZuiBatteryManagerService`。HAL 的每个 setter 都是把整数原样写进对应节点,没有换算。

| 功能 | 节点 | 取值 |
|---|---|---|
| 长期插电保护 | `/sys/class/power_supply/battery/protection_setting` | 开 = `100000 + min*1000 + max`;关 = `95100` |
| 充电上限 | `…/battery/protection_setting_eu` | `100000 + 下限*1000 + 上限`,下限 = 上限 x 回充比例/100;原厂 80% = `176080`,100% = `195100` |
| 回充比例 | `…/battery/recharge_setting` | 百分数,原厂默认 95 |
| 关电池充电 | `…/battery/charging_enable` | HAL 的 `setBatteryChargeDisabled(bool)` 把布尔原值写进去(没取反) |
| 输入挂起 | `…/usb/input_suspend` | 0 = 输入保持打开 |
| 两颗电芯 | `/sys/class/qcom-battery/fg1_*`、`fg2_*`、`battery1_manufacturer`、`battery2_manufacturer` | `cycle_count`、`soh`、`temp`、`voltage`、`current`、`activate_date`、`produce_date` |
| 旁路档位(只读) | `…/battery/bypass_setting` | HAL 的 `setBypassLevel(int)`;含义不明,只读出来看 |
| 原厂旁路充电 | (框架里的两条投票) | `input_suspend` 不挂起 + 电池充电关闭,没有单独的"旁路"节点 |

## 没在真机上核对的(都是推断)

1. 各节点的单位:`fg*_soh`、`fg*_temp` 等原样输出,键名带 `_raw`。
2. `charging_enable` 的极性:HAL 没取反,但节点名叫 enable,所以 `battery bypass on` 会先按 HAL 的写法试、看 `battery/status`,不对就换值再试一次,两个都不行就回滚并报错。试出来的值记在 `battery.conf` 的 `chg_off`。
3. 两个保护节点的取值是否被内核按上表解读。命令回包里有 `readback=`(写完读回的值),和写入不同就是内核做了换算,要据此改。
4. 节点在重启后会不会保留:所以这些设置由 broker 记在 `/data/adb/herald/battery.conf`,开机后和每约 5 分钟核对一次,被改回去了就重写。

## 真机验证顺序(从安全到有风险)

1. `heraldctl battery info`:只读。核对单位、两颗电芯的数据是否合理。
2. `heraldctl battery protect status`、`heraldctl battery limit status`、`heraldctl battery bypass status`:只读,看原始值是不是符合上表(例如保护现在是 `95100`)。
3. `heraldctl battery protect on 75 80`,再 `status` 看读回;`protect off` 恢复。
4. `heraldctl battery limit 80`,充到 80% 看是不是停;`limit off` 恢复。
5. 旁路充电放最后:电量 50% 到 80% 之间接上充电器,`heraldctl battery bypass on`,几秒后回包里 `verified=yes` 才算对;拔掉充电器、`bypass off`。

## 安全

- 旁路充电在电量 <= 15% 时拒绝开启;已开启时降到 15% 以下由守护自动关掉并去掉记忆。
- `shipping_mode`(运输模式)、`battery_maintenance*` 等节点这里**不碰**。
- 命令都只增不改,旧的 heraldctl / broker 命令保持原样。

测试:`toolkit/test-battery-plugins.sh`(假的 sysfs 树,dash 和 busybox sh 各跑一遍)。
