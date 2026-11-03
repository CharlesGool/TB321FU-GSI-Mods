# boot-assemble:读原厂 boot,把所有贡献者登记的改动一次性应用,按原参数重签,输出 $FW_OUT/boot.img。
# 必须排在所有 boot 贡献者(selinux/kernel-enforcing、kernel-builder-string…)后面。
# 登记格式和原理见本目录 README.md。
: "${FW_OUT:?}" "${FW_BOOT_STOCK:?在 firmware.conf 里设置}" "${AVB_KEY_VBMETA:?}" "${AVBTOOL:?}"
need_input FW_BOOT_STOCK
need_input AVB_KEY_VBMETA

mapfile -t files < <(contrib_list boot)
if (( ${#files[@]} == 0 )); then
    # 没有贡献者:boot 保持原厂,原样放进输出(这样可以随意关掉 boot 的贡献者模块,不用同时删本模块)。
    # 贡献者要排在本模块前面;排在后面的会在收尾时被 check_contribs 报出来。
    cp -f "$FW_BOOT_STOCK" "$FW_OUT/boot.img"
    log "没有任何模块往 boot 登记改动,boot 保持原厂(sha256 $(sha256sum "$FW_OUT/boot.img" | cut -c1-16)…)"
    contrib_consume boot
    return 0
fi

args=(--stock "$FW_BOOT_STOCK" --out "$FW_OUT/boot.img" --key "$AVB_KEY_VBMETA" --avbtool "$AVBTOOL")
for f in "${files[@]}"; do
    case "$(contrib_marker "$f")" in
        cmdline)  args+=(--cmdline "$(cat "$f")") ;;
        replace)  args+=(--replace "$(sed -n 1p "$f")" "$(sed -n 2p "$f")") ;;
        *)        die "不认识的登记类型 '$(contrib_marker "$f")'($(basename "$f")),只认 cmdline / replace" ;;
    esac
done
[[ -n ${FW_BOOT_SALT:-} ]] && args+=(--salt "$FW_BOOT_SALT")
[[ ${FW_BOOT_DROP_DUP_PROPS:-0} == 1 ]] && args+=(--drop-duplicate-props)

python3 -I "$MOD/patch_boot.py" "${args[@]}"
contrib_consume boot
