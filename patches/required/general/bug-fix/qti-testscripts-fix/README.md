# qti-testscripts-fix:开机 init 子进程 SIGABRT 两次

## 现象

每次开机 crash buffer 两条 `Fatal signal 6 (SIGABRT) … (init)`(开机约 7 秒一次、boot_completed 一次),`crash_dump` ptrace init 被拒所以没有 tombstone。功能上没有影响。

## 原因(DP11 test-v2.5 真机定位,perfetto 开机 trace + 手动 `start qti-testscripts` 复现)

| 时刻 | 来源(原厂 vendor,未改) | 上下文 | 脚本 |
|---|---|---|---|
| `on init` | `init.qti.ufs.rc`:`exec u:r:vendor-qti-testscripts:s0 -- /vendor/bin/sh /vendor/bin/init.qti.ufs.debug.sh` | 类型不存在 | 不存在 |
| `sys.boot_completed=1` | `init.qcom.rc`:`service qti-testscripts`(oneshot,`seclabel u:r:qti-testscripts:s0`) | 类型不存在 | `/product/etc/init.qcom.testscripts.sh` 不存在 |

这两个类型只在 QTI 的 userdebug 策略里有;init fork 出的子进程在 exec 之前 `setexeccon()` 失败就 `LOG(FATAL)`。原厂 ZUI user 版应该也一样。

## 修法

`qti-testscripts.cil` 追加到 plat_sepolicy.cil:只定义两个类型(加 `roletype r`),**不给任何权限**。
setexeccon 能成功,接着 execve 被 SELinux 拒绝,init 记一条 `cannot execv` 后子进程以 127 退出,不再 abort。
被拒的 transition 和 noatsecure / rlimitinh / siginh 用 dontaudit 静默。不建 permissive 域,也不改 vendor 分区。

## 验证

```bash
adb shell 'ush -c "logcat -b crash -d"' | grep -c 'Fatal signal 6.*(init)'   # 0
adb shell 'ush -c "dmesg"' | grep -i testscripts                         # 只有 init 的 cannot execv,没有 avc
```
