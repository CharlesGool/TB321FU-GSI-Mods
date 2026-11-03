# dcservice-seapp-fix:删 seapp_contexts 里指向 dcservice_app 的规则(这个域只在 Pixel 的 vendor sepolicy 里有)。
# 适用范围由文件夹决定:在 required/tangorpro/tangorpro_bp1a.250505.005/ 下,构建只在底包 ID 命中它时才跑(toolkit/lib/runmods.sh 的 scope_ok)。
# 这一版里没有这两行就跳过;有但数量不对 fix_seapp.py 会停下来让人看。
SEAPP=system_ext/etc/selinux/system_ext_seapp_contexts
if sudo test -f "$SYS/$SEAPP" && sudo grep -q 'domain=dcservice_app' "$SYS/$SEAPP"; then
    edit "$SEAPP" python3 -I "$MOD/fix_seapp.py"
    if sudo grep -q 'domain=dcservice_app' "$SYS/$SEAPP"; then die "dcservice_app 的规则还在"; fi
    log "完成"
else
    log "(底包没有 dcservice_app 的 seapp 规则,跳过)"
fi
