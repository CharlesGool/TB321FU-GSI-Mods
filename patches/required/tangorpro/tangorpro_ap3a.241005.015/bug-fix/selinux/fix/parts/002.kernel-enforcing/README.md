# selinux/kernel-enforcing — 内核命令行加 enforcing=1 selinux=1

## 做什么

让内核从第一刻起就是 SELinux Enforcing,而不是先 Permissive、等用户态翻转。这是贡献者模块:只把参数登记到产物 `boot`,真正改 boot.img 的是 [boot-assemble](../../../../../../../general/boot-kernel/boot-assemble/README.md)(登记格式也在那里,类型 `cmdline`)。

## 原理

原厂 boot 的 cmdline 是空的。这个内核开了 SELinux 的 develop 模式,不带参数启动时内核先是 Permissive,要等用户态写一次 `/sys/fs/selinux/enforce` 才变成 Enforcing。我们的 system 里由 `selinux/enforce-at-init` 的 `init.enforce.rc` 做这一次写入。

问题在于这次翻转会留下痕迹。内核在 `/sys/fs/selinux/status` 这一页里维护几个计数,任何进程都能 mmap 来读(libselinux 就是这么用的):

- `sequence`:每次切换 enforcing 或加载策略都 +2
- `policyload`:每次加载策略 +1

正常设备只加载过策略、没切换过模式,`sequence = 2 × policyload`。用户态翻转过一次,`sequence` 就比 `2 × policyload` 多出一截。Duck Detector、春秋 Native Check 报的 "app_zygote seqno split" 就是这个(检测器的具体判据没逆向过,结论来自下面 V47 的单变量实验)。

cmdline 带上 `enforcing=1` 后内核一启动就是 Enforcing,init 和 `init.enforce.rc` 再写 1 时值没变,内核不会更新计数,也就没有痕迹。`selinux=1` 显式打开 SELinux,和 V7.4/V7.5 当年的补丁保持一致。

boot header v3/v4 的 cmdline 在 header 的 offset 44,固定 1536 字节;解析和写入细节见 [assemble](../../../../../../../general/boot-kernel/boot-assemble/README.md)。

## 改动清单

不碰 boot.img,只登记一条 `cmdline` 记录。启用后(经 assemble)boot header 的 cmdline `""` → `"enforcing=1 selinux=1"`,21 字节。

## 输入

| 变量 | 说明 |
|---|---|
| `FW_BOOT_CMDLINE` | 要追加的参数,空格分隔。TB321FU 是 `enforcing=1 selinux=1`。空的话报错(不需要就构建时 `WITHOUT=selinux/fix`) |

## 依赖和顺序

排在 `boot-assemble` 前面。和 `kernel-builder-string` 互不依赖,两个可以单独开关。

## 适用范围和换底包注意

原 cmdline 里已经有 `enforcing=` / `selinux=`(已经打过补丁,或厂商自己设了)时 assemble 会失败,不覆盖别人的设置。cmdline 总长上限 1535 字节。header 不是 v3/v4 也会失败。换固件后补丁 boot 必须重打,见 [assemble](../../../../../../../general/boot-kernel/boot-assemble/README.md)。

## 踩过的坑

- **V25-A15ROOT ~ V46**:A15 线一直用原厂 boot,没打 cmdline 补丁,内核默认 Permissive,靠 `init.enforce.rc` 用户态翻转。V44 起 Momo 报开机宽容、Duck/春秋报 seqno split。
- **V47 单变量实验**(`tb321fu_pixelos_15_tangorpro_ap3a.241005.015/releases/V47-PIF-bootfix/EXPERIMENT.md`):system 不动,只换这颗补丁 boot,seqno split 红灯消失。V48 起锁 BL 后全绿,Play Integrity 过。注意那次 cmdline 和编译者字符串是一起改的,没有单独验证过哪一个起作用;按上面的原理,起作用的是 cmdline。

## 验证

刷机后:

```bash
adb shell cat /proc/cmdline | tr ' ' '\n' | grep -E '^(enforcing|selinux)='   # enforcing=1 selinux=1
adb shell getenforce                                                          # Enforcing
```

再用 Duck Detector / 春秋 Native Check 看 seqno split 那一项。

构建时:只启用本模块 + assemble,生成的 boot 里 cmdline 有这两个参数、内核字符串不变(2026-10-31 实测)。
