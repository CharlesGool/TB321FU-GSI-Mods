# rootless Zygisk 阶段 2(真机验证注入点)。纯观察:ptrace 住 init,追 zygote64 被 fork+exec 出来的那一刻,
# 读 PC 和 ELF 入口地址对比,记一行日志立刻放行,10 秒拿不到就放弃退出。不注入任何代码、不碰 sepolicy、
# 不改 zygote 的任何行为。原理和阶段 1 的本机 PoC(研究笔记里的 monitor.c)完全一样,只是寄存器结构换成
# ARM64 的 user_pt_regs.pc。实验性补丁,默认不打,要测时 WITH=herald-zygisk-fork-observer。
require_mod required/general/herald-core   # 复用已经验证过的 herald 域(permissive)和 etc/herald_payload 目录(已标 herald_exec,不用新加策略)
OE=u:object_r:herald_exec:s0

[[ -f $MOD/src/zygisk-fork-observer ]] || die "没有预编译好的 $MOD/src/zygisk-fork-observer(用 NDK 的 aarch64-linux-android21-clang -static -s 编 src/observer.c)"
put "$MOD/src/zygisk-fork-observer" etc/herald_payload/zygisk-fork-observer 0755 0:0 "$OE"
put "$MOD/files/zygisk-fork-observer.rc" etc/init/zygisk-fork-observer.rc 0644 0:0 u:object_r:system_file:s0

log "完成(观察型探针,不新增任何 sepolicy/file_contexts;二进制靠 NDK 交叉编译,源码在 $MOD/src/observer.c)"
