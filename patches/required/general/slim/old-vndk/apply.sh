# 删掉 vendor 用不上的旧版本 VNDK apex:只留原厂 vendor 的 ro.vndk.version 对应的那一个。
need_input STOCK_VENDOR_IMG
need_file apex
m=$WORK/vendor; mkdir -p "$m"
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m"
ver=$(sudo grep -h '^ro.vndk.version=' "$m/build.prop" 2>/dev/null | tail -1 | cut -d= -f2 || true)
sudo umount "$m"
if [[ ! $ver =~ ^[0-9]+$ ]]; then die "读不出原厂 vendor 的 ro.vndk.version(看到的是 '$ver')"; fi
keep=
for f in apex/com.android.vndk.v$ver.apex apex/com.android.vndk.v$ver.capex; do
    if sudo test -e "$SYS/$f"; then keep=$f; fi
done
if [[ -z $keep ]]; then die "底包里没有 vendor 需要的 VNDK v$ver,不能删别的版本"; fi
n=0
for f in $(sudo ls "$SYS/apex" | grep -E '^com\.android\.vndk\.v[0-9]+\.(apex|capex)$'); do
    [[ apex/$f == "$keep" ]] && continue
    remove "apex/$f"; n=$((n + REMOVED))
done
log "vendor 要 VNDK v$ver,保留 $keep,删了 $n 个旧版本"
