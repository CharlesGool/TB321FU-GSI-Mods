# rooted-adbd — 让 adb root 能用

> 调试补丁(`debug/rooted-adbd`),默认不打,和 [adb-on-boot](../adb-on-boot/) **互不依赖**:这个补丁只管"手动 `adb root` 之后能不能用",不管开机自动开 ADB、不管免授权,也不让 adbd 开机就是 root。

## 做什么

| 改动 | 为什么 |
|---|---|
| `build.prop`:`ro.debuggable=1` | adbd 只有 `ro.debuggable=1` 才响应 `adb root`;user 版出厂是 0。排在 `debug-off` 后面再加回来 |
| `plat_sepolicy.cil`:`(typepermissive adbd)`、`(typepermissive shell)` | 只有 uid 0 不够,user 版策略下 adbd/shell 域仍受限。照 herald 域的做法设成 permissive,AVC 照常记、不拦 |

`ro.secure` 不动(=1):adbd 开机仍是 shell 用户,要 root 时 `adb root`。

## 状态:没验证

v9 真机上 `ro.debuggable=1` 时 `adb root` 没得到可用的 root,当时没抓到失败原因(adbd 仍是 shell 用户、`service.adb.root=0`)。这个补丁是先做出来看行不行:

```
adb root
adb shell id                      期望 uid=0
adb shell getprop service.adb.root  期望 1
adb shell cat /data/misc/keystore/herald/data/pif_fingerprint.json   原来 shell 读不了的路径
```

不成功就看原因:`adb shell logcat -d | findstr adbd` 找 `avc: denied`;或者 `adb root` 的输出(`adbd cannot run as root in production builds` 说明 `ro.debuggable` 没生效)。

## 注意

- 只放进调试镜像:`ro.debuggable=1` 加 adbd/shell permissive 很容易被检测软件发现,也削弱系统隔离,会影响 [attestation-fix](../../required/general/attestation-fix/) 想达到的状态。
- 改了 `plat_sepolicy.cil` 后构建收尾会清零 `plat_sepolicy_and_mapping.sha256`,开机时 init 重编策略(首次开机会慢一点)。
- 要 root 命令又不想动策略,用 [herald-rooted-shell](../herald-rooted-shell/)(`heraldctl rsh`)。
