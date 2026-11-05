# 删掉 vendor 用不上的旧版本 VNDK apex:只留原厂 vendor 的 ro.vndk.version 对应的那一个。
# Android 17 起 VNDK 已弃用,GSI 不再带任何 com.android.vndk.v* apex;这种情况下没东西可删,直接跳过
# (不当失败)。注意:原厂 A14 vendor 仍声明 ro.vndk.version=34 —— 底包不提供 VNDK 是否影响 vendor
# 进程启动属实机范畴(见该补丁 README「换底包注意」),本补丁只管精简,不负责补 VNDK。
need_input STOCK_VENDOR_IMG
need_file apex
mapfile -t vndk < <(sudo ls "$SYS/apex" 2>/dev/null | grep -E '^com\.android\.vndk\.v[0-9]+\.(apex|capex)$' || true)
if (( ${#vndk[@]} == 0 )); then
    log "底包没有 VNDK apex(A17 起 VNDK 已弃用移除),无需精简"
else
    m=$WORK/vendor; mkdir -p "$m"
    sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m"
    ver=$(sudo grep -h '^ro.vndk.version=' "$m/build.prop" 2>/dev/null | tail -1 | cut -d= -f2 || true)
    sudo umount "$m"
    if [[ ! $ver =~ ^[0-9]+$ ]]; then die "读不出原厂 vendor 的 ro.vndk.version(看到的是 '$ver')"; fi
    keep=
    for f in apex/com.android.vndk.v$ver.apex apex/com.android.vndk.v$ver.capex; do
        if sudo test -e "$SYS/$f"; then keep=$f; fi
    done
    if [[ -z $keep ]]; then die "底包里有 VNDK apex 但缺 vendor 需要的 v$ver,不能删别的版本"; fi
    n=0
    for f in "${vndk[@]}"; do
        [[ apex/$f == "$keep" ]] && continue
        remove "apex/$f"; n=$((n + REMOVED))
    done
    log "vendor 要 VNDK v$ver,保留 $keep,删了 $n 个旧版本"
fi
