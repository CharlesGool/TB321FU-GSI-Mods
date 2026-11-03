# smooth-display — 流畅显示档位

## 做什么

设置 → 显示 →"流畅显示"开关:**开 = 不设上限(面板最高档,165Hz,系统按内容自适应)**,**关 = 120Hz**。原来关是 60Hz。

## 原理

Settings(SettingsGoogle)里的 `PeakRefreshRatePreferenceController`:
- 开:往 `Settings.System.peak_refresh_rate` 写正无穷(A15 的 `backUpSmoothDisplayAndForcePeakRefreshRate` 标志开着时;否则写面板最高档);
- 关:写 `60.0`,不碰 `min_refresh_rate`;
- 显示"开"的条件:peak 是无穷或等于面板最高档,其余都显示"关"。

Settings 是平台签名,不能改 APK 重签,所以改系统侧:`services.jar` 的 `DisplayModeDirector$SettingsObserver.updateRefreshRateSettingLocked(I)V` 读完 `min_refresh_rate` / `peak_refresh_rate`、调 4 参数版之前,加一段:

```
if (peak == 60.0f && min == 0f) peak = 120.0f;
```

存的值仍是 60 / 无穷,所以设置里开关的显示不变;只是 DisplayModeDirector 看到的上限从 60 变成 120。`heraldctl refresh set 60` 同时写 `min=60`,不满足 `min == 0`,不受影响;`range 0 60` 会被当成"关"而变成 120(要封顶 60 用 `set 60`)。

关闭时的档位用 `device.conf` 的 `SMOOTH_DISPLAY_OFF_HZ`(默认 120)。

## 改动清单

- `system/framework/services.jar`:`classes.dex` 里改一个类(`DisplayModeDirector$SettingsObserver`),其余 dex 和条目逐字节照原 jar。
- 改了 jar 会打 `mark_modified`,由 `stale-boot-image` 清掉 services 的预编译产物(所以排在它前面)。

## 依赖和顺序

无依赖;排在 `stale-boot-image` 之前(`patch.conf` 的 `BEFORE`/`WANTS`)。与别的改 services.jar 的补丁(faceunlock 等)互不冲突:各自从当前树里取 services.jar 再改。

## 换底包注意

钩子靠一个锚点定位:`mDefaultRefreshRate` 读取紧跟着 4 参数 `updateRefreshRateSettingLocked(FFFI)V` 的调用。AOSP 改了这段(换大版本)就会命中 0 处,`apply_hook.py` 退出码 1、构建失败,不会出个没打上的镜像。

## 没在真机上核对

- 构建、回编、等价核对都过(在 Mystic A15 底包的 services.jar 上跑过),但**没上真机**。
- 要确认:打开"流畅显示" `dumpsys display` 里实际可到 165;关闭后封顶 120(`heraldctl refresh status` 看 `active`);省电模式、游戏降帧等别的投票仍可能压低。

## 验证

```bash
settings get system peak_refresh_rate                  # 关 → 60.0,开 → Infinity
heraldctl refresh status                                # 关后实际最高 120
```
