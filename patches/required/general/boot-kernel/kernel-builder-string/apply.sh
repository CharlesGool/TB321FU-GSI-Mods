# kernel-builder-string:内核里的编译者字符串 build-user@build-host → androidbld@abfarmhost(等长替换)。
# 只是贡献者:把替换规则登记到产物 boot,真正改 boot.img 的是 boot-assemble。
# 登记格式见 patches/required/general/boot-kernel/boot-assemble/README.md。原理见本目录 README.md。
: "${FW_BOOT_KBUILD_FROM:?在 firmware.conf 里设置 FW_BOOT_KBUILD_FROM}" "${FW_BOOT_KBUILD_TO:?在 firmware.conf 里设置 FW_BOOT_KBUILD_TO}"
[[ ${#FW_BOOT_KBUILD_FROM} == "${#FW_BOOT_KBUILD_TO}" ]] \
    || die "\"$FW_BOOT_KBUILD_FROM\" 和 \"$FW_BOOT_KBUILD_TO\" 长度不同,不能等长替换"
[[ $FW_BOOT_KBUILD_FROM != *$'\n'* && $FW_BOOT_KBUILD_TO != *$'\n'* ]] || die "替换串不能含换行"
# 文件两行:第一行 FROM,第二行 TO
contrib_add_text boot kbuild-string "$FW_BOOT_KBUILD_FROM"$'\n'"$FW_BOOT_KBUILD_TO" replace
