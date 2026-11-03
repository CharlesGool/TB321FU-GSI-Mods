# hotspot — 热点入口

让设置和快捷设置里显示 WLAN 热点的入口。两个静态 RRO,互相独立。

| 模块 | 做什么 | 目标包 |
|---|---|---|
| [entry-settings](../../patches/required/tangorpro/hotspot-ui-fix/parts/001.settings-entry/) | 设置里显示 WLAN 热点入口 | com.android.settings |
| [entry-quicksettings](../../patches/required/tangorpro/hotspot-ui-fix/parts/002.qs-tile/) | 下拉快捷设置里显示热点磁贴 | com.android.systemui |

热点本身的行为(6GHz、名称/密码/频段覆盖)在 [wifi](wifi.md) 组:`6ghz-hotspot`、`hotspot-overrides`。入口和行为互不依赖。

构建方式同 [auto-brightness-fix](../../patches/required/general/hardware-fix/auto-brightness-fix/) 同一套:`files/` 里是预编译 APK,源码在 `src/`,用 `toolkit/lib/build-rro.sh` 重编。
