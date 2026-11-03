# slim/gsi-traces/phh-prop-handlers

## 做什么

删 `bin/phh-prop-handler.sh`,并从 `etc/init/vndk.rc` 里删掉依赖它的 14 个 `on property:...` 段落。

## 原理

`vndk.rc` 里有一批"某个 `persist.sys.phh.*` 属性被设置时,执行 `phh-prop-handler.sh`"的段落,是 phh 给各家手机做的特性开关:华硕/OPPO/小米/vsmart 的双击亮屏(dt2w)、OPPO 游戏模式和 OTG、关音频特效、CAF 音频策略、背光缩放、关音量特效、`persist.bluetooth.system_audio_hal.enabled`,还有一条 `persist.sys.phh.mainkeys`(老式实体导航键)和三条 `persist.sys.phh.restart_ril`(手机基带重启)。

它们只在对应属性被设置时才触发,而这些属性是 phh 的 Treble 设置 App 设的(底包里没有这个 App),在 TB321FU 上从来不会被设。执行用的 `phhsu_daemon` 域也不存在。所以整批是死代码。

**留下的**(不是 phh 的,或者是通用的):`on post-fs`(vndk-detect、rw-system.sh、bind usb 音频策略)、`vold.decrypt` 和 `early-boot` 的 `phh-on-data.sh`、`service phh_on_boot`、`sys.boot_completed`(启动 phh_on_boot、`/data/misc/wifi` 属主——热点要用)、`ro.sf.lcd_density` 变了重启 surfaceflinger、`vendor.debug.sf.latch_unsignaled`、`ro.vendor.radio.default_network`、`watchdogd-gsi`。

`strip_rc.py` 按 init rc 的段落(`on` / `service` / `import` 起头)处理,不是按行 sed,所以不会破坏语法。apply.sh 删完核对 `phh_on_boot` 服务和 `rw-system.sh` 的调用还在,误删就失败。

## 改动清单

- 删 `bin/phh-prop-handler.sh`。
- `etc/init/vndk.rc`:14 个段落 → 留 9 个(用 `replace` 写回,保留属主/权限/SELinux 标签)。

## 输入 / 依赖

无。

## 换底包注意

- 别的 GSI 的 `vndk.rc` 没有这些段落时,`strip_rc.py` 返回 3,模块 log 一句跳过。
- phh 以后加了新的 `persist.sys.phh.*` 段落,按头部关键字 `persist.sys.phh.` / `sys.phh.` 也会被匹配删掉。

## 验证

```bash
adb shell cat /system/etc/init/vndk.rc | grep -c "on property"   # 只剩几条,没有 phh
adb shell ls /system/bin/phh-prop-handler.sh                     # 不存在
```
