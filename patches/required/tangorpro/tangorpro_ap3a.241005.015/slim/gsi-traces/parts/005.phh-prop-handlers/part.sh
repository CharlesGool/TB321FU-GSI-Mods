# 删 phh 的属性处理脚本,以及 vndk.rc 里依赖它的 `on property:...` 段落。
# phh-on-boot.sh / phh-on-data.sh / rw-system.sh / vndk-detect 不动(见 README)。
need_file etc/init/vndk.rc
remove bin/phh-prop-handler.sh
tmp=$(mktemp -p "$WORK"); sudo cat "$SYS/etc/init/vndk.rc" > "$tmp"
rc=0; python3 -I "$MOD/strip_rc.py" "$tmp" || rc=$?
if [[ $rc == 0 ]]; then
    replace "$tmp" etc/init/vndk.rc >/dev/null; log "~ system/etc/init/vndk.rc"
elif [[ $rc == 3 ]]; then
    log "(vndk.rc 里没有 phh 的属性处理段落,跳过)"
else
    die "处理 vndk.rc 失败(strip_rc.py 退出码 $rc)"
fi
rm -f "$tmp"
# 核对:phh_on_boot 服务和 post-fs 里的 rw-system.sh 还在,没有误删
if ! sudo grep -q '^service phh_on_boot ' "$SYS/etc/init/vndk.rc"; then die "vndk.rc 里的 phh_on_boot 服务被误删了"; fi
if ! sudo grep -q 'rw-system.sh' "$SYS/etc/init/vndk.rc"; then die "vndk.rc 里 post-fs 的 rw-system.sh 被误删了"; fi
