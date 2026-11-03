#!/system/bin/sh
# 把"开发者选项 / ADB 隐藏"的规则写成 zygote 读的配置文件 /data/system/settings_compat.conf(幂等)。
#   规则源:$STATE/devhide.conf(enabled=0|1、mode=list|all)和 $STATE/devhide.names(名单,一行一个)。
#   开着且规则有效 → 写配置文件、chcon;关着或规则不全 → 删掉配置文件(= 钩子什么都不做)。
# 两个入口:开机 post-fs-data 的 herald_devhide_boot(参数 boot,顺带记下"本次开机时的配置"给 status 判断要不要重启),
#           运行时 broker 改规则后直接 sh 它(不带参数)。
# 隐藏的设置项固定为下面 DH_KEYS,值都是 0。结果写 dmesg,前缀 herald-devhide:。
STATE=${HERALD_DH_STATE:-/data/adb/herald}
CONF=${HERALD_DH_CONF:-/data/system/settings_compat.conf}
CHCON=${HERALD_DH_CHCON:-chcon}
KMSG=${HERALD_DH_KMSG:-/dev/kmsg}
BOOTCOPY=$STATE/devhide.boot
DH_KEYS="development_settings_enabled adb_enabled adb_wifi_enabled wait_for_debugger mock_location"
log() { echo "herald-devhide: $*" > "$KMSG" 2>/dev/null; }

want=; mode=list
[ -f "$STATE/devhide.conf" ] && want=$(sed -n 's/^enabled=//p' "$STATE/devhide.conf" | tail -1)
[ -f "$STATE/devhide.conf" ] && mode=$(sed -n 's/^mode=//p' "$STATE/devhide.conf" | tail -1)
[ "$mode" = all ] || mode=list
names=0; [ -f "$STATE/devhide.names" ] && names=$(grep -c . "$STATE/devhide.names")

if [ "$want" = 1 ] && { [ "$mode" = all ] || [ "$names" -gt 0 ]; }; then
    tmp=$CONF.new
    {
        echo "MODE=$mode"
        [ -f "$STATE/devhide.names" ] && sed -n 's/^\(.\)/TARGET=\1/p' "$STATE/devhide.names"
        for k in $DH_KEYS; do echo "OVER.$k=0"; done
    } > "$tmp" 2>/dev/null || { log "FAIL: 写不了 $tmp"; rm -f "$tmp"; exit 0; }
    chmod 0600 "$tmp"; chown 0:0 "$tmp" 2>/dev/null
    $CHCON u:object_r:settings_compat_file:s0 "$tmp" 2>/dev/null || log "chcon 没成功(没装 devopts-hide/hook?),zygote 可能读不到"
    mv -f "$tmp" "$CONF" || { log "FAIL: mv 到 $CONF"; rm -f "$tmp"; exit 0; }
    log "ok: mode=$mode names=$names"
else
    rm -f "$CONF"
    log "ok: 已关闭(配置文件删除)"
fi

if [ "${1:-}" = boot ]; then
    if [ -f "$CONF" ]; then cp -f "$CONF" "$BOOTCOPY" 2>/dev/null; else rm -f "$BOOTCOPY"; fi
fi
exit 0
