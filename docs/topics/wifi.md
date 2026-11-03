# wifi 组

## 解决什么问题

GSI 上的 Wi-Fi 在这类平板上有三处不合用:没有 SIM 时国家码是空的,驱动很多信道不开;Google 的 Wi-Fi 模块认定设备不支持 6GHz 热点;
热点的名称、密码、频段这些只能进系统设置页改,前端或后端没法程序化地改。
这一组用改 Wi-Fi Mainline APEX 里的 `service-wifi.jar`(smali 补丁)解决,不用 root、不用 Xposed。

三处改动各自是一个模块,能分开开关;但它们都改同一个 APEX,而 APEX 只能整体重签一次,
所以采用"贡献者 + assemble"的做法(见 [`docs/MODULE-SPEC.md`](../MODULE-SPEC.md)):三个贡献者只登记补丁,最后一个 assemble 模块统一应用、回编、重签。

## 模块

| 模块 | 做什么 | 能单独关吗 |
|---|---|---|
| [`country-code`](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/parts/001.country-code/README.md) | 国家码读 `herald_wifi_country`,默认 `DE` | 能 |
| [`band-fix`](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/parts/002.band-fix/README.md) | 设置里选 6GHz 时固定在 6GHz 频段(信道自动),`herald_6g_channel/bw/be` 设了才套用 | 能 |
| [`6ghz-hotspot`](../../patches/optional/hotspot-6ghz-unlock/README.md) | 解锁 6GHz 热点(三处判定);原厂 vendor overlay 生效时用不到 | 能。内部三个补丁缺一不可,是一个整体 |
| [`hotspot-overrides`](../../patches/optional/hotspot-control/parts/001.hotspot-custom/README.md) | `herald_ap_*` 覆盖热点名称、密码、加密、频段等 | 能。内部两个补丁必须一起开 |
| [`apex-assemble`](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md) | 一次性应用登记的补丁、回编、重签 APEX、换进树里 | 不能关:开了任何贡献者就必须有它 |

## 顺序和依赖

`MODS` 里这样写,assemble 必须在三个贡献者后面:

```
wifi-country-code
hotspot-6ghz-unlock
hotspot-overrides
wifi-apex-assemble
```

三个贡献者互相没有构建依赖,删掉其中任意几行都行(全删也行,assemble 没有登记就跳过,APEX 保持原样);顺序也可以换。
`6ghz-hotspot` 和 `hotspot-overrides` 都改 `SoftApManager.smali`,但是改的位置不同,每个补丁都能单独打到原版上。
拿它们构建时的实测结果(2026 年 10 月,Mystic GSI 的 Wi-Fi 模块,`classes.dex` 摘要):

| 启用的贡献者 | 结果 | 说明 |
|---|---|---|
| 三个全开 | 通过 | `classes.dex` sha256 `f5c8e526…`,和拆分前一个大补丁的产物逐字节一样 |
| 任意两个 | 通过 | 实测 country-code + 6ghz-hotspot、country-code + hotspot-overrides、6ghz-hotspot + hotspot-overrides |
| 任意一个 | 通过 | 实测 country-code、6ghz-hotspot、hotspot-overrides 各自单开 |
| 顺序颠倒(overrides, 6ghz, country) | 通过 | 产物和正序一样 |
| 一个都不开,只留 assemble | 通过 | 跳过,APEX 保持原样 |
| 开了贡献者但没有 assemble | 失败(按 runmods.sh 的逻辑,未单独跑) | 构建收尾 `check_contribs` 报"没有 assemble 模块处理" |
| 贡献者之一重复出现 | 失败 | assemble 报"打补丁之前就已经有标记" |

构建能过不等于设备上功能完整,运行时有两处软关系:

- **`6ghz-hotspot` 在这台设备上需要 `country-code`**(国家码留在 `US` 时驱动拒绝 6GHz AP,热点秒关)。别的设备不一定。
- **`hotspot-overrides` 的 `herald_ap_band` 含 6G 位时要有 `6ghz-hotspot`**,否则系统认为设备不支持 6GHz 热点。

不支持的"组合":只开 `hotspot-overrides` 的一半补丁。它的两个补丁在同一个模块里,不提供拆开的选项。

## 整组怎么单独发布

拿 `patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/parts/001.country-code/`、`patches/optional/hotspot-6ghz-unlock/`、`patches/optional/hotspot-control/parts/001.hotspot-custom/`、`patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/` 加 `toolkit/`(用到 `toolkit/apex/`、`toolkit/avb/avbtool.py`、`toolkit/lib/`、`toolkit/build.sh`、`toolkit/run-module.sh`)和 `docs/MODULE-SPEC.md`。
需要的参数和 key(AVB 私钥、AOSP testkey)不在组里,用户自己提供,写在设备的 `conf.d/wifi.conf` 里,变量说明见
[apex-assemble 的"输入"](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md#输入)。

设备相关的、移植到别的设备要改的值:

| 值 | 在哪 |
|---|---|
| 默认国家码 `DE` | `country-code/patches/01-WifiCountryCode.diff` |
| 6GHz 可用频率列表(59 个) | `6ghz-hotspot/patches/01-ApConfigUtil.diff`、`02-WifiServiceImpl.diff`(两处要一致) |
| 6GHz 默认信道 37、默认带宽 80MHz | `6ghz-hotspot/patches/03-SoftApManager-6ghz.diff` |
| 签名 key、APEX 路径 | `conf.d/wifi.conf` |

补丁按 Android 15 的 Wi-Fi 模块(版本 350820380)做,换版本要重做,步骤见 [apex-assemble](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md#换底包补丁打不上怎么办)。

## 设备上的 Settings.Global 键一览

| 键 | 模块 |
|---|---|
| `herald_wifi_country` | country-code |
| `herald_6g_channel`、`herald_6g_bw`、`herald_6g_be` | 6ghz-hotspot |
| `herald_ap_ssid`、`herald_ap_pass`、`herald_ap_sec`、`herald_ap_band`、`herald_ap_hidden`、`herald_ap_maxclients`、`herald_ap_autoshut`、`herald_ap_timeout_min`、`herald_ap_clientctl`、`herald_ap_macrand` | hotspot-overrides |

取值表在各模块 README 里。
