# qesdk-seccomp-fix:从原厂 vendor 现取两份 seccomp 策略 → 在末尾追加 files/*.add → 开机 bind 到 /vendor。
# 高通原文件不进仓库,仓库里只有追加的那几行。原理见 README.md。
source "$TOOLKIT/lib/vendorbind.sh"

# <vendor 相对路径> <追加文件> <vendor-bind 名>
seccomp_fix() {
    local rel=$1 add=$2 name=$3 base out sc
    base=$(basename "$rel")
    vendor_stock_get "$rel" "$WORK/$base.stock"
    # 追加的系统调用原文件里已经有了,就说明换了固件,别再盲目追加
    for sc in $(sed -n 's/^\([a-z0-9_]*\):.*/\1/p' "$add"); do
        grep -q "^$sc:" "$WORK/$base.stock" && die "$rel 里已经有 $sc,固件和预期不一样,先核对再改 $add"
    done
    out=$WORK/$base
    cat "$WORK/$base.stock" "$add" > "$out"
    log "$base: 追加 $(grep -c '^[a-z]' "$add") 个系统调用 → $(sha256sum "$out" | cut -c1-12)…"
    # 原文件 sha256 现算,不写死(toolkit/vendor-bind/README.md「踩过的坑」V66)
    vendor_bind_add "/vendor/$rel" "$out" "$(sha256sum "$WORK/$base.stock" | cut -d' ' -f1)" \
        "$name" u:object_r:vendor_configs_file:s0
}

seccomp_fix etc/seccomp_policy/qesdksec.policy         "$MOD/files/qesdksec.add"         qesdk-secmgr-seccomp
seccomp_fix etc/seccomp_policy/qsap_qapeservice.policy "$MOD/files/qsap_qapeservice.add" qsap-qape-seccomp
