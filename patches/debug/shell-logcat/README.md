# selinux/shell-logcat

## 做什么

Enforcing 下让 `adb shell` 能运行 `logcat`。

## 原理

Mystic 的 `plat_sepolicy.cil` 没有给 `shell` 域执行 `logd_exec`(`/system/bin/logcat`)的权限。Permissive 时看不出来,切到 Enforcing 后 `adb shell logcat` 报 Permission denied,排查问题抓不到日志。追加一条 allow:

```
(allow shell logd_exec (file (getattr execute read open map execute_no_trans)))
```

## 改动清单

- `plat_sepolicy.cil` 追加上面一条(由构建框架在收尾时清零 `plat_sepolicy_and_mapping.sha256`,强制 init 开机重编策略)。

## 输入 / 依赖

无。

## 换底包注意

如果新底包的策略已经给了 shell 执行 logcat 的权限,这条是重复 allow,无害。

## 踩过的坑

- V7.3 实测 Enforcing 后 shell 执行 logcat 被挡,V7.4 补上。

## 验证

```bash
adb shell logcat -d | head
```
