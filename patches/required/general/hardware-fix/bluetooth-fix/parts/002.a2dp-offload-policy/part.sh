# 从原厂 vendor 现取 sku_pineapple 音频策略 → 生成不走 offload 的版本 → 开机 bind 到 /vendor。(不依赖别的模块:vendor_bind_add 首次调用时自己装开机脚本)
source "$TOOLKIT/lib/vendorbind.sh"

POLICY_REL=${BT_POLICY_REL:-etc/audio/sku_pineapple/audio_policy_configuration.xml}

vendor_stock_get "$POLICY_REL" "$WORK/policy.stock.xml"
python3 -I "$MOD/make_policy.py" "$WORK/policy.stock.xml" "$WORK/audio_policy_configuration.xml"

# 原文件的 sha256 现算(vendor 里的文件开机时必须和它一致才 bind)
vendor_bind_add "/vendor/$POLICY_REL" "$WORK/audio_policy_configuration.xml" \
    "$(sha256sum "$WORK/policy.stock.xml" | cut -d' ' -f1)" bt-a2dp-offload-policy u:object_r:vendor_configs_file:s0
