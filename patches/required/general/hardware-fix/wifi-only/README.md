# TB321FU：按纯 Wi-Fi 平板处理（去掉双卡、基带相关项）

## 现象

- DevCheck 显示支持双卡双待。
- 设置 → 网络和互联网里有"排查移动网络连接问题"（通话、短信和流量问题）。
- 本机实际没有基带：`ro.baseband=apq`，vendor 脚本见到 apq 就停掉 qcrild，并设置 `ro.vendor.radio.noril=yes`。

## 原因（2026-11-09 在 test-v2.0 上查实）

| 来源 | 现状 | 影响 |
|---|---|---|
| `/product/etc/build.prop` 第 136 行 | `persist.radio.multisim.config=dsds` | `TelephonyManager.getActiveModemCount()` 直接返回 2，`telephony.registry` 里有 Phone Id 0、1 两个槽。DevCheck 的"双卡双待"就来自这里 |
| `/vendor/etc/permissions/android.hardware.telephony.mbms.xml` | 声明了 `android.hardware.telephony.mbms` | 系统特性里有一项电话类特性 |
| `/vendor/etc/permissions/noRil/apq_excluded_telephony_features.xml` | 高通给 apq 平台准备的排除清单，把电话类特性全部设为 unavailable | 放在子目录里，SystemConfig 不读子目录，**从来没生效** |
| framework-res | `config_voice_capable`、`config_sms_capable`、`config_mobile_data_capable` 都是默认值 true，没有任何 overlay 改 | 系统认为本机能打电话、发短信、用流量 |

dsds 只被 vendor 的 `init.class_main.sh` 用来决定是否启动第二个 qcrild，而 apq 平台在那之前就已经退出了，所以去掉它对 vendor 没有任何影响。`/data/property/persistent_properties` 里也没有存这个值，删掉 build.prop 里那一行就会生效。

## 改法（三处，都在系统侧，不碰 vendor）

### 1. product build.prop：删掉 dsds

```bash
sed -i '/^persist\.radio\.multisim\.config=/d' product/etc/build.prop
```

删掉后，属性为空，`getActiveModemCount()` 走 UNKNOWN 分支。设备既不能打电话、发短信，也不能用移动数据，所以返回 **0**。

### 2. 系统特性：`system/etc/permissions/tb321fu-wifi-only.xml`

内容就是 vendor 那份 noRil 清单再加上 `telephony.euicc`。`unavailable-feature` 不管特性是哪个分区声明的，都会移除。

```
system/etc/permissions/tb321fu-wifi-only.xml -> /system/etc/permissions/tb321fu-wifi-only.xml   root 0644  u:object_r:system_file:s0
```

### 3. RRO

`src/`:把 `config_voice_capable`、`config_sms_capable`、`config_mobile_data_capable` 设为 false。priority 325(接 tb321fu 系列编号),只在 `ro.product.vendor.device=TB321FU` 时生效。产物 `files/tb321fu-wifi-only.apk`(`REBUILD_RRO=1` 时现编),装到 `/product/overlay/`。

## 刷入后的效果（未上机，按 AOSP 逻辑推断）

- DevCheck：SIM 卡槽数为 0，不再显示双卡。
- 设置：预计不再显示"排查移动网络连接问题"。这一项来自 Google 的 Settings，具体判断条件没有反编译确认；如果它还在，再单独查。
- 锁屏不显示"紧急呼叫"。
- 和 Pixel Tablet、原厂 ZUI 的纯 Wi-Fi 版一样，Play 商店会按纯 Wi-Fi 设备过滤"必须有电话功能"的应用。这是正常的。
- 飞行模式、Wi-Fi、蓝牙、网络共享（Wi-Fi 热点、USB）不受影响。
- 会议类应用的 VoIP 来电（自管理的 ConnectionService）不受影响。

## 验证

```bash
adb shell getprop persist.radio.multisim.config                  # 空
adb shell pm list features | grep -i telephony                   # 无输出
adb shell cmd overlay lookup android android:bool/config_voice_capable   # false
adb shell dumpsys telephony.registry | grep -c 'Phone Id'        # 0
```

然后打开 DevCheck 和设置 → 网络和互联网各看一眼。

## 回退

把三处改动撤掉即可。build.prop 那一行可以原样加回去。
