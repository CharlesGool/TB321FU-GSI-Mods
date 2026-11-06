# wifi-country-code

## 做什么

Wi-Fi 国家码由 `Settings.Global` 的 `herald_wifi_country` 决定,没设置时用 `DE`。

贡献者模块:只把补丁登记给 [`wifi-apex-assemble`](../../../wifi-apex-assemble/README.md),由它统一回编和重签 APEX。自己不动 APEX。

## 原理

`WifiCountryCode` 是 Wi-Fi 服务里管国家码的类。它从电话模块拿到国家码后调用私有方法
`setTelephonyCountryCode(String)` 记下来,再由状态机下发给驱动(HAL / wificond)。驱动按国家码决定哪些信道能用、
能不能当 AP 发射。平板没有 SIM 卡时电话国家码是空的,驱动用默认域,很多信道不开放。

补丁 `patches/01-WifiCountryCode.diff` 在 `setTelephonyCountryCode` 最开头插一段代码,把参数换掉,后面的原有逻辑不动:

| `herald_wifi_country` 的值 | 效果 |
|---|---|
| 没设置 | 换成 `DE` |
| 两个字符(如 `de`、`JP`) | 转大写后换成它 |
| `NONE`(不分大小写) | 不换,用电话模块给的原值(没 SIM 时是空,等于"飞行模式状态") |
| 其它长度的字符串 | 当成没设置,换成 `DE` |

整段包在 `catchall` 里,读设置出任何异常都回落到 `DE`,不会影响原有流程。这和 LSPosed 模块
`io.github.mirukurusan.wificountrycode` 的做法一样(它 hook 的也是这个方法,在执行前改参数),只是直接烤进 jar 里。

生效时机:这个方法被调用时才会重读设置。改完重启一定生效;V57 实测把值改成 DE 后没重启、重开热点也生效了,
但没有专门验证过每次都这样,保险起见改完重启。

**设备相关:默认值 `DE`。** 这台机器(高通 WCN785x,驱动 kiwi_v2)在 `US` 下把 6GHz 频点全部标成
`NO-IR | INDOOR_ONLY`(hostapd 日志 `Frequency 6135 not allowed for AP mode, flags 0x13803 NO-IR`),热点秒关;
`DE` 下 6GHz AP 能开。代价是 DE 的 5GHz 没有 149–169 信道。别的设备、别的地区按自己的驱动行为选默认值,
改 `patches/01-WifiCountryCode.diff` 里的 `const-string p1, "DE"`(改完核对标记,见"换底包注意")。

## 改动清单

- 经 assemble 间接改 `system/apex/com.google.android.wifi.apex` 里 `javalib/service-wifi.jar` 的 `classes.dex`:
  `WifiCountryCode.setTelephonyCountryCode` 开头插入一段。别的什么都不动。
- 只改一个类,和同组其它模块的补丁不在同一个文件,互不影响。

## 输入

`conf.d/wifi.conf` 里的 `WIFI_APEX_FILE`(只用来检查底包里有没有这个 APEX)。国家码的取值不在构建参数里,在设备上用 `Settings.Global` 设。

## 依赖和顺序

无依赖。要排在 `wifi-apex-assemble` 前面。和同组其它贡献者互相独立,可以单独开,顺序随意(MODS 里按 country-code → 6ghz-hotspot → hotspot-overrides 排)。
`6ghz-hotspot` 在这台设备上要靠 `DE` 之类的国家码才能真正开起来(见那边的 README),但构建上不依赖本模块。

## 适用范围和换底包注意

补丁按 Android 15 的 Wi-Fi 模块做(模块版本 350820380)。`apply.sh` 检查底包里有 APEX;补丁能不能打上由 assemble 检查,
上下文用 `patch --fuzz=0` 一字不差地比,`setTelephonyCountryCode` 的签名或 `.locals` 变了就会在 assemble 里报
"`…WifiCountryCode.diff` 打不上"。重做补丁的步骤见 [`apex-assemble` README](../../../wifi-apex-assemble/README.md#换底包补丁打不上怎么办)。
补丁的校验标记是 `const-string v1, "herald_wifi_country"`,改补丁时要保留。

## 踩过的坑

- **V49**:`WifiCountryCode` 不在 services.jar,在 Wi-Fi Mainline APEX 里,所以要改 APEX。
- **V55 → V57**:国家码从写死 `US` 改成读 `herald_wifi_country`,加了 `NONE`;US 下 6GHz 全是 NO-IR,设 DE 后 6GHz 热点成功。

## 验证

```bash
adb shell settings put global herald_wifi_country DE      # 改国家码,重启生效
adb shell dumpsys wifi | grep -iE 'mTelephonyCountryCode|mDriverCountryCode'   # 应为 DE 或你设的值
```
