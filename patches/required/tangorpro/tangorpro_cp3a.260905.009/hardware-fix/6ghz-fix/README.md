# 6ghz-fix — 6GHz 修复

> **CP3A(Android 17)适配版**(V1.1)。两段 smali 注入(`WifiCountryCode.setTelephonyCountryCode`、
> `SoftApManager.startSoftAp`)的注入代码与 bp1a 逐字相同,只把上下文锚对到 A17 的 `service-wifi.jar`
> 重新生成了 diff:A17 下方法体的 `.line` 号变了(385→388、841→926),且编译器把
> `new StringBuilder();append(..)` 改成了 `new StringBuilder("..")`,老 diff 的尾部上下文对不上。
> 另:A17 底包 Wi-Fi APEX 是压缩格式 `com.google.android.wifi.capex`,`conf.d/wifi.conf` 的
> `WIFI_APEX_FILE` 已指向它(assemble 会解压、改 `service-wifi.jar`、重签成未压缩 `.apex`)。
> 离线验证:两 diff 均干净打上,apextool 重打包 + 重签 + AVB 校验通过,service-wifi.jar 回读逐字节一致。

> 一个补丁(`6ghz-fix`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

## 解决什么问题

这台平板的 Wi-Fi 芯片(高通 WCN785x)支持 6GHz 热点,但 GSI 上有两处挡着:

1. 没有 SIM 时 Wi-Fi 国家码是空的,驱动在 `US` 之类的国家码下把 6GHz 频点标成 `NO-IR | INDOOR_ONLY`,热点秒关;`DE` 下 6GHz AP 能开。
2. 设置页里选 6GHz 时,系统下发的是"2.4+5+6 混选 + 自动选信道"的配置,驱动的自动选信道会选到 5GHz(V54 日志 `startSoftAp: channels {7=0}`,实际 ch48),热点开在 5GHz 上。

| 部分 | 做什么 |
|---|---|
| [001.country-code](parts/001.country-code/) | 国家码读 Settings 键 `herald_wifi_country`,默认 `DE` |
| [002.band-fix](parts/002.band-fix/) | 配置里只有一个频段键且含 6GHz 位时,把频段固定成 6GHz,**信道交给驱动自动选,不固定带宽和 802.11be**;`herald_6g_channel/bw/be` 设了才套用 |

能不能在设置里选到 6GHz 取决于 Wi-Fi 资源开关 `config_wifiSoftap6ghzSupported`:原厂 vendor 的 overlay 生效时本来就是 true(V103 清数据刷机实测),不生效时要打可选的 [hotspot-6ghz-unlock](../../../../../optional/hotspot-6ghz-unlock/)。

APEX 只能整体重签一次,两个部分只"登记"补丁(`contrib_add wifi-service-jar`),真正打包重签在 [wifi-apex-assemble](../wifi-apex-assemble/)。
热点名称/密码自定义和 `heraldctl wifi|hotspot` 命令在可选的 [hotspot-control](../../../../../optional/hotspot-control/)。

更多背景见 [docs/topics/wifi.md](../../../../../../docs/topics/wifi.md)。
