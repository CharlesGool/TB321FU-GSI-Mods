# identity/version-label — 版本号

## 做什么

把 `ro.build.display.id` 写成 `$DISPLAY_ID`(现在是产物名,如 `pixelos_tangorpro_ap3a.241005.015_110-beta_optional`)。设置里"关于平板电脑 → 版本号"显示的就是它,刷机后一眼能看出刷的是哪一版。

## 原理

改 `system/build.prop` 里的一行(GSI 原值是 `Ported.By.MysticTech`)。

`system_ext/etc/build.prop`、`product/etc/build.prop` 里要是也有这个键,一并改:init 按 system → system_ext → vendor → odm → product 读,同名 ro.* 后读的覆盖先读的。新版 MysticGSI(DP11 起)在 product 里写了 `ro.build.display.id=Ported.Using.MysticGSI.Tool`,只改 system 时设置里的版本号一直是这个(2026-11-06 test-v1.4 真机)。key 不存在会报错(用的是 `prop`,不加 `--add`)。

它单独成模块,因为版本号每个版本都要变,和其它机型身份的改动没关系。`DISPLAY_ID` 里带 `${VERSION}`,构建时有产物名(`IMAGE_NAME`)就显示产物名,没有才用 `VERSION`。

## 改动清单

- 改 `system/build.prop`:`ro.build.display.id`
- `system_ext/etc/build.prop`、`product/etc/build.prop` 有这个键时同样改

## 依赖和顺序

无依赖,顺序随意。

## 输入(`conf.d/identity.conf`)

`DISPLAY_ID`

## 换底包注意

底包的 build.prop 里要有 `ro.build.display.id`,没有就构建失败(AOSP 系的 GSI 都有)。

## 验证

```bash
adb shell getprop ro.build.display.id
```
