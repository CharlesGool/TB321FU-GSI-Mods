# herald-zygisk-timing-probe

## 做什么

纯只读测量,不改变任何已有行为。rootless Zygisk 调研到了一个绕不开的架构问题:将来要在 `zygote`
真正 fork 第一个子进程**之前**让一个常驻监控服务完成 `PTRACE_SEIZE`,但从 `post-fs-data` 触发
到 `on zygote-start` 真正执行 `start zygote` 之间,**到底有多宽的时间窗口**,只能上真机量,
读 init.rc 源码猜不出来(背景见本机 PoC `stage1-findings.md`,ptrace 截停机制本身已经在开发机上
验证过,和 Android 版本无关)。

这个模块只做一件事:在 `post-fs-data` 落一行自己的 `uptime`,不碰 ptrace、不碰 sepolicy、不改
`herald-start.sh` 一个字。拿到这个时间点之后,事后 `adb shell` 读 `zygote64`/`zygote` 自己的
`/proc/<pid>/stat` 第 22 个字段(`starttime`,开机以来的 clock tick 数,内核免费记好的,
不用额外改 zygote 就能拿到)算出真实的 uptime,两者一减就是窗口宽度。

## 原理(大致)

- `files/zygisk-timing-probe.rc`:一个 `exec_start`(同步、init 等它跑完才往下走)的 oneshot
  服务,挂在 `on post-fs-data`,`seclabel u:r:herald:s0`——这条触发点和域跟 `patches/required/general/tango/parts/005.zygote32`
  的 `tango-guard.sh` 完全一样,V883 真机已经验证过这个时机点能跑、不影响开机。
- `files/zygisk-timing-probe.sh`:读 `/proc/uptime`(开机以来的秒数,10ms 精度),连带一个
  墙钟时间戳,落到 `/metadata/herald_log/zygisk-timing-probe.log`(V91 起已经是 shell 可读的落盘位
  置,`herald-start.sh` 自己也写这个目录)。
- `herald` 域本身是 `(typepermissive herald)`(见 `patches/required/general/herald-core/sepolicy_herald.cil`),这个探针复用
  同一个域、同一个已经标好 `herald_exec` 的 `etc/herald_payload` 目录,**不新增任何 sepolicy/
  file_contexts 规则**——风险面比 `tango-guard.sh` 还小,因为它完全不触碰 `/dev`、不 insmod、
  不改属性,就读一个文件、写一个文件。

## 改动清单

- `etc/herald_payload/zygisk-timing-probe.sh`、`etc/init/zygisk-timing-probe.rc`。

## 输入

无。

## 依赖和顺序

`require_mod required/general/herald-core`(要用它的 `herald` 域和 `etc/herald_payload` 目录)。和其他模块互不影响,
默认不打(在 `MODS_OFF` 里),要量的时候 `WITH=herald-zygisk-timing-probe` 构建,不跟正式版本走。

## 换底包注意

和底包无关,纯用标准 Linux `/proc` 接口,AOSP 任何版本都一样。

## 验证

```bash
adb shell cat /metadata/herald_log/zygisk-timing-probe.log
# 预期类似:
#   post-fs-data uptime: 3.21 1.98
#   wall: 2026-11-xx 10:00:03.214

# zygote 自己的开机以来 tick 数(第 22 个字段),除以 100 得秒数(Android HZ 通常是 100)
adb shell cat /proc/$(adb shell pidof zygote64)/stat
# 如果设备上也起了 32 位 zygote(tango/zygote32 装了的话):
adb shell cat /proc/$(adb shell pidof zygote)/stat 2>/dev/null

# 把两边的 uptime 相减,就是 post-fs-data 到 zygote 真正起来之间的时间窗口(毫秒级)
```

把 `zygisk-timing-probe.log` 和两条 `/proc/<pid>/stat` 的内容贴回来即可,不需要在设备上再做任何
计算或解析。
