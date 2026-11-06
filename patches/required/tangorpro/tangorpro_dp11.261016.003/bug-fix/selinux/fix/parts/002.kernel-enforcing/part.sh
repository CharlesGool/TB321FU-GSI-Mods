# selinux/kernel-enforcing:给内核命令行加 enforcing=1 selinux=1。
# 只是贡献者:把参数登记到产物 boot,真正改 boot.img 的是 boot-assemble。
# 登记格式见 patches/required/general/boot-kernel/boot-assemble/README.md。原理见本目录 README.md。
[[ -n ${FW_BOOT_CMDLINE:-} ]] || die "FW_BOOT_CMDLINE 是空的(在 firmware.conf 里设置,例如 \"enforcing=1 selinux=1\");不需要这个改动就构建时 WITHOUT=selinux/kernel-enforcing"
[[ $FW_BOOT_CMDLINE != *$'\n'* ]] || die "FW_BOOT_CMDLINE 不能含换行"
contrib_add_text boot cmdline "$FW_BOOT_CMDLINE" cmdline
