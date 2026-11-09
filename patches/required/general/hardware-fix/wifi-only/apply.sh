# wifi-only:纯 Wi-Fi 平板。原理见 README.md(vendor 的 noRil 排除清单放在子目录里,SystemConfig 不读,从来没生效)。
PB=product/etc/build.prop
need_file $PB
if sudo grep -q '^persist\.radio\.multisim\.config=' "$SYS/$PB"; then
    edit $PB sed -i '/^persist\.radio\.multisim\.config=/d'
    ! sudo grep -q '^persist\.radio\.multisim\.config=' "$SYS/$PB" || die "没删掉 $PB 里的 persist.radio.multisim.config"
else
    log "($PB 里没有 persist.radio.multisim.config)"
fi
put "$MOD/files/tb321fu-wifi-only.xml" etc/permissions/tb321fu-wifi-only.xml 0644 0:0 u:object_r:system_file:s0
APK=$MOD/files/tb321fu-wifi-only.apk
[[ ${REBUILD_RRO:-0} == 1 ]] && "$TOOLKIT/lib/build-rro.sh" "$MOD/src" "$APK" 1
[[ -f $APK ]] || die "缺 $APK(先跑 toolkit/lib/build-rro.sh $MOD/src $APK)"
put "$APK" product/overlay/tb321fu-wifi-only.apk 0644 0:0 u:object_r:system_file:s0
