#!/system/bin/sh
# rootless Zygisk 阶段 1(真机量窗口):post-fs-data 一到就落自己的 uptime,纯只读测量,
# 不碰 ptrace、不碰 sepolicy、不改任何已有行为。和 zygote 真正起来的时刻(另外用 adb 读
# /proc/$(pidof zygote64)/stat 的 starttime 字段)对比,就是"注入监控服务最晚什么时候必须
# 完成 PTRACE_SEIZE"这条窗口的真实宽度。
mkdir -p /metadata/herald_log 2>/dev/null
{
  echo "post-fs-data uptime: $(cat /proc/uptime)"
  date '+wall: %Y-%m-%d %H:%M:%S.%3N' 2>/dev/null
} >> /metadata/herald_log/zygisk-timing-probe.log 2>&1
