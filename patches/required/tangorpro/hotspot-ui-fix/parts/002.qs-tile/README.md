# qs-tile — 快捷设置热点磁贴

## 做什么

下拉快捷设置里显示热点磁贴。

## 原理

SystemUITitan 的自动生成 RRO 把 `config_show_wifi_tethering` 关了。这个 overlay(目标包 `com.android.systemui`,优先级 20)设回 true。

## 改动清单

- 加 `product/overlay/treble-overlay-lenovo-tb321fu-systemui.apk`(预编译件与 V66 逐字节相同)。

## 输入 / 依赖

无。和 [settings-entry](../001.settings-entry/) 成对。

## 换底包注意

同 settings-entry。

## 验证

下拉快捷设置,编辑磁贴能找到热点。
