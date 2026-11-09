# 从原厂 vendor 现取 libqcodec2_v4l2codec.so → 输出缓冲申请超时后"距上次输入 >1s 就放弃"改成永远重试 → 开机 bind 到 /vendor。
source "$TOOLKIT/lib/vendorbind.sh"
python3 -I -c 'import elftools' 2>/dev/null || die "缺 python3 模块 pyelftools(apt install python3-pyelftools)"

QC2_REL=${VF_QCODEC2_REL:-lib64/libqcodec2_v4l2codec.so}

vendor_stock_get "$QC2_REL" "$WORK/qcodec2.stock.so"
python3 -I "$MOD/patch_qcodec2_alloc_retry.py" "$WORK/qcodec2.stock.so" "$WORK/libqcodec2_v4l2codec.so" \
    | while IFS= read -r l; do log "$l"; done
# 复查:补丁版必须报"已打补丁",且和原文件只差 1 条指令(4 字节内)
chk=$(python3 -I "$MOD/patch_qcodec2_alloc_retry.py" --check "$WORK/libqcodec2_v4l2codec.so")
[[ $chk == 已打补丁* ]] || die "补丁版复查没报'已打补丁':$chk"
n=$( { cmp -l "$WORK/qcodec2.stock.so" "$WORK/libqcodec2_v4l2codec.so" || true; } | wc -l)   # cmp 有差异时退出码 1
(( n >= 1 && n <= 4 )) || die "补丁版和原文件差了 $n 个字节,预期 1~4 个"

# 原文件 sha256 现算,不要写死(toolkit/vendor-bind/README.md「踩过的坑」V66)
vendor_bind_add "/vendor/$QC2_REL" "$WORK/libqcodec2_v4l2codec.so" \
    "$(sha256sum "$WORK/qcodec2.stock.so" | cut -d' ' -f1)" video-qcodec2-alloc-retry u:object_r:vendor_file:s0
