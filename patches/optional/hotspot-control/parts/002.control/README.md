# 002.control — 热点命令(接入 herald-core)

给 [herald-core](../../../../required/general/herald-core/) 加 Wi-Fi 热点的命令,没有核心时跳过(`mod_ran required/general/herald-core`)。

- `plugins/wifi.sh`(broker 插件):`wifi_get`(热点运行状态 + 系统热点设置 `sys_*` 行)、`wifi_put`(覆盖项白名单 + 取值校验后写 Settings.Global)、`hotspot_start` / `hotspot_stop` / `hotspot_start_system` / `hotspot_status`、`wifi_status`;`HERALDP_SELFTEST` 加 dumpsys wifi 自检;`HERALDP_ATTACH` 登记 `wifi_put` 的 key=value 附带数据。
- `heraldctl.d/wifi.sh`(heraldctl 插件):`heraldctl wifi show|status|set|clear`、`heraldctl hotspot start|start-system|stop|status`。

覆盖项的键(`herald_6g_*` 由必选 6ghz-fix 的 002.band-fix 的 smali 补丁读,`herald_wifi_country` 由 6ghz-fix 的 001.country-code 读,`herald_ap_*` 由本补丁的 001.hotspot-custom 读)在 `wifi_put` 白名单里一并放行,不论 hotspot-6ghz-unlock 选没选。

## 系统热点配置(V68,`wifi_get` 末尾的 `sys_*` 行)

前端想在没设覆盖项时显示系统当前的热点设置。这份配置在 wifi 模块的私有目录里(App 和 adb shell 都读不了),broker 用 root 读。

- 文件:`/data/misc/apexdata/com.android.wifi/WifiConfigStoreSoftAp.xml`;依次尝试 `com.android.wifi`、`com.google.android.wifi`、任意 `apexdata/*wifi*`、`/data/misc/wifi`。herald 域是 permissive,读不会被 SELinux 拦(会记 avc)。
- 解析用 sh + grep/sed(设备上没有 python/awk)。字段名按 AOSP 的 `SoftApConfigurationXmlUtil`:`WifiSsid`(加引号的文本;不带引号的是十六进制,按字节解码)/旧版 `SSID`、`Passphrase`、`SecurityType`、`Band`(每个频段一条,按位或)/旧版 `ApBand`、`HiddenSSID`、`MaxNumberOfClients`、`AutoShutdownEnabled`、`ShutdownTimeoutMillis`(毫秒,除 60000 得分钟)、`ClientControlByUser`、`MacRandomizationSetting`。XML 转义(`&amp;` 等)还原。
- 读不到的一项整行省略;文件读不了输出一行 `err wifi_sys …`。只读,不改设置。
- 格式见 `doc/herald-backend-api.md`。**真机未验证**:字段名是按 AOSP 源码的记忆写的,Android 15 的实际文件内容以真机为准。`toolkit/tests/test-herald-protocol.sh` 里有用模拟文件做的回归。

## 踩过的坑

- V64:macrand 失效(SoftApManager 构造时已把随机化置 NONE)、autoshut=0 失效。
- V63:信道填 70 时热点直接起不来 → `wifi_put` 对取值做校验,不合法的不写。
- V74:`hotspot status` 热点关着时 dumpsys 里没有 `mCurrentSoftApInfoMap`,不能当"读不到";`SoftApInfo.toString` 的 `frequency= 5180` 等号后有空格。
