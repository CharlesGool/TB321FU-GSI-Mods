# identity/version-label — 版本号

## 做什么

把 `ro.build.display.id` 写成 `$DISPLAY_ID`(现在是产物名,如 `pixelos_tangorpro_ap3a.241005.015_110-beta_optional`)。设置里"关于平板电脑 → 版本号"显示的就是它,刷机后一眼能看出刷的是哪一版。

## 原理

改 `system/build.prop` 里的一行(GSI 原值是 `Ported.By.MysticTech`)。

`system_ext/etc/build.prop`、`product/etc/build.prop` 里要是也有这个键,一并改:init 按 system → system_ext → vendor → odm → product 读,同名 ro.* 后读的覆盖先读的。新版 MysticGSI(DP11 起)在 product 里写了 `ro.build.display.id=Ported.Using.MysticGSI.Tool`,只改 system 时设置里的版本号一直是这个(2026-11-06 test-v1.4 真机)。key 不存在会报错(用的是 `prop`,不加 `--add`)。

它单独成模块,因为版本号每个版本都要变,和其它机型身份的改动没关系。`DISPLAY_ID` 里带 `${VERSION}`,构建时有产物名(`IMAGE_NAME`)就显示产物名,没有才用 `VERSION`。

## 每版触发一次"系统升级"(identity V1.4)

PackageManager 只有在 `PackagePartitions.FINGERPRINT`(`ro.build.fingerprint` 和 `ro.{system,vendor,odm,oem,product,system_ext}.build.fingerprint` 的摘要)变了时,才把开机当成系统升级:重新推算系统应用的 ABI、重新给默认权限、作废包解析缓存。
我们各版的指纹都沿用底包的(incremental 一样),**保留数据刷新版**时 PM 只当普通重启,沿用 `/data/system/packages.xml` 里旧版的记录。

DP11 user-v1.1 真机就是这样坏的:WebView 从"占位 + 压缩包"换成完整 APK(`webview-full`),保留数据刷入后 PM 沿用了占位包的 ABI(空),`libwebviewchromium.so` 加载不了;把同一个 APK 当更新装一遍(重新推算 ABI)就好了。

所以这里把 `ro.system_ext.build.fingerprint` 的 incremental 后面加上本版标记 `.<sha1(IMAGE_NAME) 前 8 位>`,例如 `.../16708287.7c5abca8:user/release-keys`,每个产物名都不一样。
只改 system_ext 这一条:Play / PIF 看的 `ro.build.fingerprint`、`isBuildConsistent()` 比对的 `ro.system` / `ro.vendor` 指纹都不动。代价是保留数据刷新版后首次开机会慢一些(重新优化应用)。

## 改动清单

- 改 `system/build.prop`:`ro.build.display.id`
- `system_ext/etc/build.prop`、`product/etc/build.prop` 有这个键时同样改
- `ro.system_ext.build.fingerprint`(`system_ext/etc/build.prop`,`system/build.prop` 里有的话一起改):incremental 加本版标记

## 依赖和顺序

无依赖,顺序随意。

## 输入(`conf.d/identity.conf`)

`DISPLAY_ID`

## 换底包注意

底包的 build.prop 里要有 `ro.build.display.id`,没有就构建失败(AOSP 系的 GSI 都有)。

## 验证

```bash
adb shell getprop ro.build.display.id
adb shell getprop ro.system_ext.build.fingerprint   # .../<incremental>.<8 位标记>:user/release-keys
```
