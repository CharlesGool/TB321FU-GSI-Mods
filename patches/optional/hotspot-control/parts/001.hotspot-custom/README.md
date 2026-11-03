# hotspot-overrides

## 做什么

用 `Settings.Global` 的 `herald_ap_*` 键改普通热点的名称、密码、加密、频段、隐藏、最大连接数、自动关闭、批准连接、MAC 随机化,
不用进系统设置页。没设置的项沿用系统热点设置。

贡献者模块:只把两个补丁登记给 [`wifi-apex-assemble`](../../../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md),自己不动 APEX。

## 原理

调用链:开热点 → `ActiveModeWarden` 建 `SoftApManager`(构造时从 `WifiApConfigStore` 取配置、
`randomizeBssidIfUnset` 生成随机 BSSID、`configureInternalConfiguration` 按配置定 `mTimeoutEnabled`)
→ 状态机 `IdleState` 收到 `CMD_START` → … → `startSoftAp()` → `WifiNative` → hostapd HAL。

两个补丁:

- `patches/01-SoftApManager-overrides.diff`:给 `SoftApManager` 加一个新的静态方法 `heraldApplyApOverrides(SoftApManager)`。
  它只对**普通热点(tethered,`targetMode == 1`)**生效,"附近分享"之类 App 开的本地热点不动。
  从当前配置建 `SoftApConfiguration.Builder`,把设置了的键逐项套上,`build()` 后写回 `mCurrentSoftApConfiguration`,
  再把 `mTimeoutEnabled` 按新配置的 `isAutoShutdownEnabled()` 同步(构造时已经按旧配置定过,不同步的话 autoshut=0 不生效,V64 修)。
- `patches/02-IdleState-call.diff`:在 `IdleState` 处理 `CMD_START` 的最开头(记下 requestor WorkSource 之后)调用这个方法。
  放在 `CMD_START` 而不是 `startSoftAp()`:V61 放在 `startSoftAp()` 里十项全不生效(确切原因没查明),V63 挪到这里后生效,
  这里早于系统自己的频段、安全性检查。

**两个补丁必须一起开**:02 调用 01 加的方法,单开 02 smali 能编过(编译器不查方法是否存在),但一开热点就会 `NoSuchMethodError`,所以不提供拆开的选项。所以它们是同一个模块的两个补丁,不能拆开。

每次开普通热点会打一行 logcat(tag `HeraldWifi`):`herald_ap_* applied=<套用了几项> macrand=<取值,-1=没设> config=<最终配置>`。
出错是 `herald_ap_* override failed, keep system config` 加异常栈,**这一次的覆盖全部不生效**,热点按系统配置照常开,不会带崩 system_server。
改完要把热点关掉再开。系统设置页显示的名称、密码不会变,以别的设备实际看到的为准。

### `herald_ap_*` 取值

| 键 | 合法取值 | 说明 |
|---|---|---|
| `herald_ap_ssid` | 非空字符串,UTF-8 不超过 32 字节 | 热点名称。空字符串 = 不覆盖 |
| `herald_ap_pass` | 8–63 个字符 | 密码。只设密码不设 `herald_ap_sec` 时沿用当前加密方式 |
| `herald_ap_sec` | 0 / 1 / 2 / 3 | 开放 / WPA2 / WPA2+WPA3 过渡 / WPA3(`SoftApConfiguration.SECURITY_TYPE_*`)。只设加密不设密码时沿用当前密码。**6GHz 必须用 3**,否则系统把 6GHz 去掉、回到 5GHz |
| `herald_ap_band` | 1–7 | 位组合:1=2.4G、2=5G、4=6G,可相加。含 6G 要让 6GHz 真能开,需要启用 [`hotspot-6ghz-unlock`](../../../hotspot-6ghz-unlock/README.md) |
| `herald_ap_hidden` | 0 / 1 | 隐藏名称(非 0 都当 1) |
| `herald_ap_maxclients` | 0 或正整数 | 最大连接数,0 = 不限 |
| `herald_ap_autoshut` | 0 / 1 | 没设备连接时自动关闭 |
| `herald_ap_timeout_min` | 正整数(分钟) | 自动关闭前等多久。≤0 当没设置 |
| `herald_ap_clientctl` | 0 / 1 | 新设备连接要手动批准 |
| `herald_ap_macrand` | 0 / 1 / 2 | 热点 BSSID:0 = 不随机化(用接口硬件 MAC),1 = 固定的随机 MAC,2 = 每次开热点换一个。系统热点设置里手动指定了 BSSID 时不生效 |

**校验:** `herald_ap_*` 在 smali 里只区分"没设置"(取不到或负数)和"设置了",范围不在 smali 里查——
值不合法时 `SoftApConfiguration.Builder` 会抛 `IllegalArgumentException`,被 catch 住,这一次的 `herald_ap_*` 全部不生效。
所以写这些键的前端/后端要先按上表校验(免 root 核心的 `wifi_put` 就是这么做的)。
非数字字符串对整数键等于没设置(`Settings.Global.getInt` 带默认值时解析失败返回默认值)。

**macrand 的实现细节(V64):** 构造 `SoftApManager` 时 `randomizeBssidIfUnset` 已经写了随机 BSSID 并把随机化设置改成 NONE,
这时直接 `setMacRandomizationSetting(1/2)` 会让 `build()` 抛 "A BSSID had configured but MAC randomization setting is not NONE"。
所以只在 `mIsUnsetBssid`(用户没指定 BSSID)时先 `setBssid(null)` 再设随机化,`build()` 之后对 1/2 再调一次
`WifiApConfigStore.randomizeBssidIfUnset`(且要求能力位支持 MAC 定制)。`dumpsys wifi` 里配置的 `MacRandomizationSetting`
永远显示 0,判断是否生效看 BSSID。实测 `macrand=0` 时 BSSID 是 `02:03:7f:…`(高通驱动由出厂 MAC 派生)。

## 改动清单

经 assemble 间接改 `javalib/service-wifi.jar` 的 `classes.dex`:

| 补丁 | 类 / 方法 | 校验标记 |
|---|---|---|
| `01-SoftApManager-overrides.diff` | `SoftApManager` 新增 `heraldApplyApOverrides`(在 `onL2Connected` 前面) | `.method public static heraldApplyApOverrides(…)V` |
| `02-IdleState-call.diff` | `SoftApManager$SoftApStateMachine$IdleState` 的 `CMD_START` 分支插一行调用 | `->heraldApplyApOverrides(Lcom/android/server/wifi/SoftApManager;)V` |

## 输入

`conf.d/wifi.conf` 里的 `WIFI_APEX_FILE`。各项参数在设备上用 `Settings.Global` 设。

## 依赖和顺序

构建上无依赖,要排在 `wifi-apex-assemble` 前面。和 `hotspot-6ghz-unlock` 的 `03-SoftApManager-6ghz.diff` 都改 `SoftApManager.smali`,
位置不同,各自单独能打上,开关任意组合(已验证)。想让 `herald_ap_band` 含 6G 的热点真的开在 6GHz,要同时启用 `6ghz-hotspot`;
只开本模块设 6G 位时,GSI 默认认为设备不支持 6GHz 热点,热点开不到 6GHz(没有专门测过具体回落到哪)。

## 适用范围和换底包注意

补丁按 Android 15 的 Wi-Fi 模块做。`01` 的上下文是 `isOweTransition` 的结尾和 `onL2Connected` 的签名,
`02` 的上下文是 `IdleState.processMessageImpl` 里 `fputmRequestorWs` 调用附近的几行;`SoftApManager` 里的字段名
(`mCurrentSoftApConfiguration`、`mSpecifiedModeConfiguration`、`mIsUnsetBssid`、`mTimeoutEnabled`、`mCurrentSoftApCapability`、
`mWifiApConfigStore`)变了,回编会报 smali 错。重做步骤见 [`apex-assemble` README](../../../../required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md#换底包补丁打不上怎么办)。

## 踩过的坑

- **V61 → V63**:通用覆盖放在 `startSoftAp()` 里全部不生效,挪到 `IdleState` 的 `CMD_START` 开头后生效,并加了 `HeraldWifi` 日志。
- **V63 → V64**:macrand 设 1/2 让整次覆盖失败(BSSID 和随机化设置冲突);autoshut=0 不生效(`mTimeoutEnabled` 没同步)。细节见上文。
- **V58 → V59**:读用户设置的补丁要先对照框架源码确认取值范围,并整体 try/catch。

## 验证

```bash
adb shell settings put global herald_ap_ssid MyHotspot     # 关掉再开热点
adb shell logcat -d | grep HeraldWifi                      # 应有 herald_ap_* applied=1 …
```

别的设备看到的热点名称应已变成 `MyHotspot`。
