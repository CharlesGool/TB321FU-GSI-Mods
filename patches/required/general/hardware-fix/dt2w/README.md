# dt2w — 双击唤醒

TB321FU(Novatek 触摸,原厂内核)硬件和驱动都支持双击唤醒:往 `/proc/gesture_control` 写 1,灭屏双击时驱动上报 `KEY_WAKEUP`,系统亮屏。
GSI 上用不了,原因有三个:

- 原厂由 ZUI 设置经 `vendor.lenovo.hardware.touchscreen` HAL 写这个节点,GSI 里没有调用方,节点一直是 0。
- Pixel 的"点按唤醒"(`Secure.double_tap_to_wake`)走 PowerManager → Power HAL `setMode(DOUBLE_TAP_TO_WAKE)`,高通 Power HAL 不实现。
- GSI 的 `config_supportDoubleTapWake=false`,设置页把开关藏了。

节点标签是通用 `proc`,平台策略不给 init / vendor_init 写 `proc`,所以做成 herald 插件(herald 域 permissive),不改 sepolicy、不动 vendor:

1. broker 启动后用 fabricated overlay(`com.android.shell:tb321fu_dt2w`)把 `android:bool/config_supportDoubleTapWake` 设为 true,
   **设置 → 显示 → 其他显示控制 → 点按唤醒**出现。overlay 存在 /data,只在缺失或被关时重建。
2. 以 `Secure.double_tap_to_wake` 为唯一开关(没设过 = 开),broker 每 5 秒空闲检查一次同步到节点;设置页拨开关最多 5 秒生效,驱动复位节点也会被写回。

PowerManager 之后会调 Power HAL `setMode(DOUBLE_TAP_TO_WAKE)`,高通 HAL 报 unsupported,无害。

## 用法

```bash
adb shell heraldctl dt2w status      # ok dt2w on / node value=1 / overlay=on
adb shell heraldctl dt2w off
adb shell heraldctl dt2w on
```

`heraldctl diag` 里有 `== dt2w` 一段;`heraldctl log | grep dt2w` 有开机那一行。灭屏双击应亮屏,`dumpsys power` 里 `mLastWakeReason=6`(WAKE_KEY)。

## 镜像里的改动

- `etc/herald_payload/plugins/dt2w.sh`(0644 root,`herald_exec`)
- `etc/heraldctl.d/dt2w.sh`(0644 root,`system_file`)

## 验证

插件逻辑在真机上用照抄 broker `herald_sys`/`blog` 的 harness 验证过(overlay 重建/启用、节点同步、off、设置拨回、模拟驱动复位后写回、用法错误);fabricate 路径手动验证过。
2026-11-09 打进 DP11 test-v1.8-cust_bebug 上机验证:设置里出现"点按唤醒",灭屏双击亮屏。

## 已知

- 灭屏时触摸控制器停在手势模式,待机功耗略增。
- 只写 0/1,原厂 `gesture_control` 的其他位(画字母手势等)不处理。
