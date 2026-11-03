# rootless Zygisk 阶段 1(真机量窗口)。纯只读测量:post-fs-data 一到就把自己的 uptime 落盘,
# 不碰 ptrace、不碰 sepolicy、不改 herald-start.sh 一个字——跟事后用 adb 读 zygote 自己的 /proc/pid/stat
# starttime 字段对比,量出"注入监控服务最晚什么时候必须完成 PTRACE_SEIZE"这条窗口的真实宽度。
# 实验性模块,默认不打(MODS_OFF),要量时 WITH=herald-zygisk-timing-probe。见 README"验证"一节。
require_mod required/general/herald-core   # 复用已经验证过的 herald 域(permissive)和 etc/herald_payload 目录(已标 herald_exec,不用新加策略)
OE=u:object_r:herald_exec:s0

put "$MOD/files/zygisk-timing-probe.sh" etc/herald_payload/zygisk-timing-probe.sh 0755 0:0 "$OE"
put "$MOD/files/zygisk-timing-probe.rc" etc/init/zygisk-timing-probe.rc 0644 0:0 u:object_r:system_file:s0

log "完成(只读探针,不新增任何 sepolicy/file_contexts)"
