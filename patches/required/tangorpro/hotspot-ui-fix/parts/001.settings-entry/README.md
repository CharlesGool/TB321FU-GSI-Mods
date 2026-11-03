# settings-entry — 设置里的热点入口

## 做什么

设置里显示"WLAN 热点"入口。

## 原理

tangorpro 的 `SettingsGoogleTangorproOverlay` 把设置里的热点入口关了(Pixel Tablet 不显示)。这个 overlay(目标包 `com.android.settings`,优先级 20,高于 tangorpro 自带的 10 / 1)把 `config_show_wifi_hotspot_settings` 设回 true。

## 改动清单

- 加 `product/overlay/treble-overlay-lenovo-tb321fu-settings.apk`(预编译件与 V66 逐字节相同)。

## 输入 / 依赖

无。和 [qs-tile](../002.qs-tile/) 成对出现:设置里和下拉快捷设置里各有一个入口,可以只开一个。

## 换底包注意

底包里的 Pixel overlay 优先级如果比 20 高,这个 overlay 会被盖住,要提优先级。

## 验证

设置 → 网络和互联网 里能看到热点。
