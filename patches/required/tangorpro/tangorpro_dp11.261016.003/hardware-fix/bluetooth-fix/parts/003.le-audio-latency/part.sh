# 从原厂 vendor 现取 btaudio_offload_if.so → LE 会话的 peerDelayUs(微秒)先 /1000 再上报 → 开机 bind 到 /vendor。
source "$TOOLKIT/lib/vendorbind.sh"
python3 -I -c 'import elftools, capstone' 2>/dev/null || die "缺 python3 模块 pyelftools / capstone(apt install python3-pyelftools python3-capstone)"

BTA_REL=${BT_LE_LATENCY_REL:-lib64/btaudio_offload_if.so}

vendor_stock_get "$BTA_REL" "$WORK/btaudio.stock.so"
python3 -I "$MOD/patch_btaudio_le_latency.py" "$WORK/btaudio.stock.so" "$WORK/btaudio_offload_if.so" \
    | while IFS= read -r l; do log "$l"; done
chk=$(python3 -I "$MOD/patch_btaudio_le_latency.py" --check "$WORK/btaudio_offload_if.so")
[[ $chk == *已打补丁* ]] || die "补丁版复查没报'已打补丁':$chk"
n=$( { cmp -l "$WORK/btaudio.stock.so" "$WORK/btaudio_offload_if.so" || true; } | wc -l)   # cmp 有差异时退出码 1
(( n >= 1 && n <= 64 )) || die "补丁版和原文件差了 $n 个字节,预期 1~64 个"

# 原文件 sha256 现算,不要写死(toolkit/vendor-bind/README.md「踩过的坑」V66)
vendor_bind_add "/vendor/$BTA_REL" "$WORK/btaudio_offload_if.so" \
    "$(sha256sum "$WORK/btaudio.stock.so" | cut -d' ' -f1)" bt-le-audio-latency u:object_r:vendor_file:s0
