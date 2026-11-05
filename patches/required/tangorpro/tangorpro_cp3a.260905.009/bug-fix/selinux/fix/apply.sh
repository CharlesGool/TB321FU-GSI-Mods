# selinux/fix:SELinux 修复——开机即 Enforcing。system 里删 Mystic 的 permissiver、early-init 就 setenforce 1;boot 的内核命令行加 enforcing=1 selinux=1。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。001 改 system 树,002 往 boot 登记(boot-assemble 写进 boot.img)。
run_parts
