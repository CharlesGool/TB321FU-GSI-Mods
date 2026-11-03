# hotspot-6ghz

## 做什么

设置里能选 6GHz 热点,并真正在 6GHz 上开起来。

贡献者模块:只把三个补丁登记给 [`wifi-apex-assemble`](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md),自己不动 APEX。

## 原理

Google 的 Wi-Fi 模块默认认为设备不支持 6GHz 热点:`ServiceWifiResourcesGoogle.apk` 里的两个开关
`config_wifi6ghzSupport`、`config_wifiSoftap6ghzSupported` 出厂是 false,本该由厂商 vendor/product 分区的 RRO 改成 true。
这台机器的厂商 RRO(`vendor/overlay/WifiResMainlineTarget_spf.apk`、`product/overlay/KirbyRowWifiResOverlay.apk`)
确实写了 true,但在 GSI 上没生效(没查清原因)。改资源 APK 本身行不通(见 apex-assemble README 的"不能碰"和 V50),所以直接改判定逻辑。
沿调用链一共有三道门,V51–V54 一道一道试出来的,**缺一不可**,所以三个补丁在同一个模块里:

1. **能力位**:`ApConfigUtil.isSoftApBandSupported(Context, int)`(`patches/01-ApConfigUtil.diff` 第二处)。
   它决定 `SoftApCapability` 里 6GHz 那一位(`SOFTAP_FEATURE_BAND_6G_SUPPORTED`,0x80)是否置位,也决定后面会不会去查 6GHz 信道。
   补丁:参数 band == 4(`SoftApConfiguration.BAND_6GHZ`)时直接返回 true。
2. **服务端信道列表**:`ApConfigUtil.getAvailableChannelFreqsForBand(int, WifiNative, Resources, boolean)`(`01-ApConfigUtil.diff` 第一处)。
   原逻辑要 HAL / wificond 报告的信道和资源里配置的信道取交集,6GHz 的资源配置是空的,交集为空。
   补丁:band == 4 时直接返回 59 个频率,5955、5975 … 7115 MHz(信道 1–233,步长 4)。
   注意返回的是**频率(MHz)**,不是信道号(V52 返回信道号,dumpsys 里显示成 `[-1, …]`)。补丁不看第 4 个参数,一律返回 MHz。
3. **设置页用的信道列表**:`WifiServiceImpl.lambda$getUsableChannels$132(int band, int mode, int filter)`(`patches/02-WifiServiceImpl.diff`)。
   设置页(`SettingsGoogle` 的 `WifiHotspotRepository.isChannelAvailable`)判断 6GHz 选项是否可选,调的是公开 API
   `WifiManager.getUsableChannels(WIFI_BAND_6_GHZ=8, OP_MODE_SAP=2)`,这条路直接问 `WifiNative`,不经过上面两处。
   补丁:band == 8 且 mode 含 2 时返回同样 59 个频率的 `WifiAvailableChannel` 列表(构造参数第二、三个直接透传 mode、filter)。
   只改 1、2 时设置里 6GHz 仍是灰的(V53)。

开起来以后固定在 6GHz 频段、以及信道/带宽/802.11be 的覆盖(`herald_6g_*` 三个键)不在本补丁,在必选的 [6ghz-fix 的 002.band-fix](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/parts/002.band-fix/);设置页选 6GHz 时下发的"混选 + ACS"配置会被驱动选到 5GHz,那一段固定 6GHz 信道的逻辑也在那边。

**设备相关(移植到别的设备要改):**

- 59 个频率来自这台机器驱动的报告(wificond 日志里列出的 6GHz 频点)。别的芯片/地区可用的频点不同,
  要按自己设备的日志改 `01-ApConfigUtil.diff`、`02-WifiServiceImpl.diff` 两个补丁里的列表(两处要一致)。
- 默认信道 37、默认带宽 80MHz 写在 `03-SoftApManager-6ghz.diff` 里。
- 驱动是否允许 6GHz 当 AP 取决于国家码(见 [`wifi-country-code`](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/parts/001.country-code/README.md))。

## 清数据刷机时可能用不到(2026-11-01 V103 真机)

V103 没打本补丁(热点控制里只登记了国家码、热点自定义、6GHz 控制 4 个补丁),**清数据刷机后 6GHz 热点直接能用**。
`cmd overlay list` 里 `com.google.android.wifi.resources` 下 `overlay.target`、`overlay.pineapple`、`pixel` 三个 overlay 都是启用状态;
其中 `overlay.pineapple` 就是原厂 vendor 的 `WifiResMainlineTarget_spf.apk`,里面 `config_wifi6ghzSupport` 和 `config_wifiSoftap6ghzSupported` 都是 true。
也就是说厂商自己的开关这次生效了,框架本来就认为支持 6GHz 热点。原厂 product 分区的 `KirbyRowWifiResOverlay.apk` 在 GSI 上不存在,不影响结果。
上面"没生效(没查清原因)"的情况出现在保数据刷机的设备上,猜测和旧的 overlay 状态有关(同类问题见 `optional/overlay-idmap-reset`),没有对照验证。
国家码仍要是 `DE`(热点控制的 `001.country-code`),否则驱动在 `US` 下把 6GHz 标成 `NO-IR`,热点秒关。
所以本补丁只在 vendor overlay 没生效的设备上才需要。

## 改动清单

经 assemble 间接改 `javalib/service-wifi.jar` 的 `classes.dex`:

| 补丁 | 类 / 方法 | 校验标记 |
|---|---|---|
| `01-ApConfigUtil.diff` | `ApConfigUtil.getAvailableChannelFreqsForBand`、`isSoftApBandSupported` 开头插入 | `const/16 v1, 0x1bcb` |
| `02-WifiServiceImpl.diff` | `WifiServiceImpl.lambda$getUsableChannels$132` 开头插入(`.locals 0` → `3`) | `const/16 v2, 0x1bcb` |
| `03-SoftApManager-6ghz.diff` | `SoftApManager.startSoftAp` 开头插入 | `const-string v6, "herald_6g_channel"` |

## 输入

`conf.d/wifi.conf` 里的 `WIFI_APEX_FILE`。信道、带宽、BE 在设备上用 `Settings.Global` 设。

## 依赖和顺序

构建上无依赖,要排在 `wifi-apex-assemble` 前面。`03` 和 [`hotspot-overrides`](../../optional/hotspot-control/parts/001.hotspot-custom/README.md) 的补丁都改 `SoftApManager.smali`,
但改的是不同位置,各自单独都能打上,两者开关任意组合都行(已验证,见组 README 的组合表)。
运行时:这台设备要配合 `country-code`(DE 之类)才能真正开出 6GHz 热点;只开本模块、国家码保持 US 时能编过,但热点会被驱动拒绝。

## 适用范围和换底包注意

补丁按 Android 15 的 Wi-Fi 模块做。上下文用 `--fuzz=0`,`.locals`、方法名(尤其是 `lambda$getUsableChannels$132` 这种带编号的 lambda,
换版本编号会变)变了就在 assemble 里报"打不上"。重做步骤见 [`apex-assemble` README](../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md#换底包补丁打不上怎么办)。
新加的标签统一用 `:herald_` 前缀,避免和原有标签撞。

## 踩过的坑

- **V50**:为了 6GHz 改资源 APK,重签后被 PackageManager 拒装,system_server 崩溃(详见 apex-assemble)。结论:改 jar 里的判定逻辑。
- **V51 → V52**:只截了 `getAvailableChannelFreqsForBand` 不够,上游 `isSoftApBandSupported` 先挡住了。改判定要从最上游的门查起。
- **V52 → V53**:信道函数返回的是频率 MHz,不是信道号。
- **V53 → V54**:设置页用的是 `getUsableChannels` 公开 API,另一条路,要单独改。V54 起 6GHz 可选。
- **V54 → V55**:混选频段 + ACS 时驱动选到 5GHz,加了"含 6GHz 就固定 6GHz 信道"。
- **V58 → V59**:`herald_6g_bw` 取值表凭记忆写错(以为 320MHz 是 7),设了非法值抛异常没接住,system_server 软重启。之后所有读用户设置的补丁都先对照框架源码确认取值,并整体 try/catch。

## 验证

```bash
adb shell dumpsys wifi | grep -iE 'SupportedChannelListIn6g|6g'    # 6GHz 信道列表不为空
adb shell logcat -d | grep HeraldWifi                                  # 开一次 6GHz 热点后应有 "herald_6g applied config=…"
```

系统设置 → 热点里 6GHz 可选;加密选 WPA3、频段选 6GHz 开热点,用另一台支持 6GHz 的设备能扫到、能连上。
