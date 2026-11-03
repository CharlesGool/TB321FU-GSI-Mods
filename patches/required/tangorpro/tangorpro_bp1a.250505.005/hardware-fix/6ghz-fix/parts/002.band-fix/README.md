# 002.band-fix — 设置里选 6GHz 时固定在 6GHz 频段

## 做什么

设置页选 6GHz 热点时,把热点固定在 6GHz **频段**上;**信道交给驱动自动选,不固定信道和带宽**(2026-11-01 起,以前固定信道 37、带宽 80MHz)。
另外保留三个可选的覆盖键,设了才套用:`herald_6g_channel` / `herald_6g_bw` / `herald_6g_be`(信道、带宽、802.11be),不设就不碰。
能不能开出 6GHz 热点由 Wi-Fi 资源开关决定:原厂 vendor 的 overlay 生效时本来就支持,不生效时要打可选的 [optional/hotspot-6ghz-unlock](../../../../../../../optional/hotspot-6ghz-unlock/);
还要配合 [001.country-code](../001.country-code/)(DE),驱动才允许 6GHz 当 AP。

## 原理

开起来以后还有一道:设置页选 6GHz 时下发的配置往往是"2.4+5+6 混选 + ACS 自动选信道",驱动的 ACS 会选到 5GHz
(V54 日志 `startSoftAp: channels {7=0}`,实际 ch48)。所以 `patches/03-SoftApManager-6ghz.diff` 在 `SoftApManager.startSoftAp()` 开头加了一段:
**配置里只有一个频段键、且这个键含 6GHz 位时**,把信道表重建成只有 6GHz 一个频段、信道为 0(自动),并套用设了的 `herald_6g_*`。
这一段不区分热点类型,整段包在 `try/catch(Exception)` 里,出错就保持原配置,不会带崩 system_server。
套用成功会打一行 logcat(tag `HeraldWifi`):`herald_6g applied config=…`;出错是 `herald_6g override failed, keep system config` 加异常栈。

### `herald_6g_*` 取值

键在 `Settings.Global`,**没设置就不套用**(信道自动,带宽和 802.11be 沿用系统配置)。改完要把热点关掉再开。

| 键 | 合法取值 | 说明 |
|---|---|---|
| `herald_6g_channel` | 1–233,且 (信道−1) % 4 == 0 | 固定 6GHz 信道,例如 37(PSC 信道,6135 MHz)。不合法或没设就是自动 |
| `herald_6g_bw` | -1 / 2 / 3 / 4 / 6 / 11 | 自动 / 20 / 40 / 80 / 160 / 320 MHz(`SoftApInfo.CHANNEL_WIDTH_*`)。其它值或没设就不改 |
| `herald_6g_be` | 0 / 1 | 非 0 开 802.11be(Wi-Fi 7),没设或 0 不改 |

**还没验证:** 信道设为自动(0)时驱动在 6GHz 上的自动选信道能不能正常开出热点,没有实测过。以前固定信道 37 是因为自动选信道会选到 5GHz,那是因为配置里 2.4+5+6 混选,现在只剩 6GHz 一个频段,理论上应该不会。
如果开不出来,adb 设 `settings put global herald_6g_channel 37` 退回固定信道。

三项都在 smali 里自己校验,不合法就当没设(V59 教训:`setMaxChannelBandwidth` 收到非法值会抛异常)。
6GHz 热点的加密必须是 WPA3(`SoftApConfiguration.SECURITY_TYPE_WPA3_SAE`),否则系统会把 6GHz 去掉、回到 5GHz;
这个要靠设置页选 WPA3,或者用 [`hotspot-overrides`](../../../../../../../optional/hotspot-control/parts/001.hotspot-custom/README.md) 的 `herald_ap_sec=3`。

已知的实测结果(TB321FU,V61–V64):320MHz 实际回落到 160,`-1` 自动也是 160;`herald_6g_be=1` 写进了配置但热点仍是 Wi-Fi 6;
平板同时连着 5GHz Wi-Fi 时芯片要求同信道,6GHz 热点会被压回 5GHz。

## 改动清单

| 补丁 | 类 / 方法 | 校验标记 |
|---|---|---|
| `01-SoftApManager-6ghz.diff` | `SoftApManager.startSoftAp` 开头插入 | `const-string v6, "herald_6g_channel"` |

## 依赖和顺序

构建上无依赖;要排在 `wifi-apex-assemble` 前面。和可选的 `hotspot-control/001.hotspot-custom` 的补丁都改 `SoftApManager.smali`,但位置不同,各自单独都能打上。
运行时要配合 `001.country-code`(DE 之类)才能真正开出 6GHz 热点。
