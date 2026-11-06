# selinux/enforce-at-init

## 做什么

删掉 Mystic 的 permissiver,在 early-init 阶段单次 `setenforce 1`。装完开机不再有"先 Permissive 再翻回 Enforcing"的两段式。

## 原理

Mystic 底包带了 `etc/init/permissiver.rc` + `bin/permissiver.sh`,在 early-init 里 `setenforce 0`,要等 boot_completed 才翻回 Enforcing,开机大半时间是 Permissive,检测器一抓一个准。

删掉后换成自己的 `init.enforce.rc`,在 early-init 写一次 `/sys/fs/selinux/enforce`。**真正让内核一开始就是 Enforcing 的是固件阶段的 [`selinux/kernel-enforcing`](../002.kernel-enforcing/README.md)**(内核命令行 `enforcing=1`);有了它,这里写 1 时值没变,内核不更新 `/sys/fs/selinux/status` 的 sequence 计数,不留痕迹。没有那个补丁 boot 时,这里的写入是一次真实的 Permissive→Enforcing 翻转,会被 "app_zygote seqno split" 抓到(原理见 selinux/kernel-enforcing 的 README)。

## 改动清单

- 删 `etc/init/permissiver.rc`、`bin/permissiver.sh`(没有就跳过)。
- 加 `etc/init/init.enforce.rc`(0644 root:root `system_file`)。

## 输入

无。

## 依赖和顺序

无依赖。建议配合 `selinux/kernel-enforcing`。

## 换底包注意

别的 GSI 没有 permissiver 时只 log 一句跳过,仍会装 `init.enforce.rc`。

## 踩过的坑

- V7 "全删不切":实测这版 Mystic 的 init 加载策略后不会自动把 enforce 设 1,什么都不碰设备停在 Permissive,Duck Detector 直接报 SELinux Permissive。所以必须自己写一次 1。
- V25-A15ROOT ~ V44:`NO_PERMISSIVE_FLIP=1` 开关在重新跑构建时漏传,Mystic 的 permissiver 一路存活到 V44,Momo 实机测出"开机宽容"(V45 修)。

## 验证

```bash
adb shell getenforce                         # Enforcing
adb shell ls /system/etc/init/permissiver.rc  # No such file
```
