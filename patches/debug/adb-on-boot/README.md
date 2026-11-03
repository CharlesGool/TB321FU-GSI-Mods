# adb-on-boot — 开机自动开 ADB、免授权

> 一个补丁(`debug/adb-on-boot`),内部两个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。给开发和排错用,默认不打。

`required/general/bug-fix/debug-off` 把 Mystic 的调试段整段删了,让系统是干净的 user 状态。调试补丁在执行顺序上排在必须打和可选的后面,可以把需要的部分再盖回来:

| 部分 | 做什么 |
|---|---|
| `001.on-boot` | 开机自动启用 ADB:`persist.sys.usb.config=adb,mtp`,不用先去开发者选项里打开 |
| `002.no-auth` | 免授权 ADB:`ro.adb.secure=0`(连电脑不弹授权框,system 和 system_ext 两处都改) |

不碰 `ro.debuggable`、`ro.secure`:`adb shell` 还是 shell 用户,要 root 用 [herald-rooted-shell](../herald-rooted-shell/)。

## 顺序

`AFTER=(required/general/bug-fix/debug-off)`:两个都打时必须排在 `debug-off` 后面,否则会被它改回去。只打本补丁不打 `debug-off` 也行。

## 注意

- 选法:`WITH=debug`(一次选所有调试补丁)或 `WITH=adb-on-boot`。默认不打。
- **不要用在日常使用的镜像上**:免授权 ADB 意味着任何接上的电脑都能直接进 shell,这类调试状态也可能被检测软件发现,会影响 [attestation-fix](../../required/general/attestation-fix/) 想达到的状态。
- `persist.sys.usb.config` 是出厂默认,用户在设置里改过会以用户的为准。

## 验证

没上真机验证。刷机后接电脑:`adb devices` 应在开机后直接可见且不弹授权框。
