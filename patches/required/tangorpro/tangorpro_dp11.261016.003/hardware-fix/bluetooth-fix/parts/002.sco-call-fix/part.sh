# 从原厂 vendor 现取 audio.primary → 4 处 cbz 改 nop → 开机 bind 到 /vendor。
source "$TOOLKIT/lib/vendorbind.sh"

AHAL_REL=${BT_AHAL_REL:-lib64/hw/audio.primary.pineapple.so}

vendor_stock_get "$AHAL_REL" "$WORK/ahal.stock.so"
python3 -I "$MOD/patch_ahal.py" "$WORK/ahal.stock.so" "$WORK/audio.primary.pineapple.so"

# 原文件的 sha256 现算,不要写死(V66 的教训,见 README)
vendor_bind_add "/vendor/$AHAL_REL" "$WORK/audio.primary.pineapple.so" \
    "$(sha256sum "$WORK/ahal.stock.so" | cut -d' ' -f1)" bt-sco-ahal-patch u:object_r:vendor_file:s0
