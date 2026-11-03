# 指纹和 build 描述符:从原厂固件(STOCK_SYSTEM_IMG,可选 STOCK_VENDOR_IMG)现取,overlay 进三份 build.prop。
need_file build.prop
need_file product/etc/build.prop
need_file system_ext/etc/build.prop
need_input STOCK_SYSTEM_IMG

# 1. 从原厂镜像读 build.prop(换固件后自动跟着变)
m=$WORK/stock; mkdir -p "$m"
sudo mount -o loop,ro "$STOCK_SYSTEM_IMG" "$m"
sudo cat "$m/system/build.prop" > "$WORK/stock_system.prop"; sudo umount "$m"
vprop=
if [[ -n ${STOCK_VENDOR_IMG:-} && -f $STOCK_VENDOR_IMG ]]; then
    sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m"; sudo cat "$m/build.prop" > "$WORK/stock_vendor.prop"; sudo umount "$m"
    vprop=$WORK/stock_vendor.prop
fi
python3 -I "$MOD/stock_overlay.py" "$WORK/stock_system.prop" $vprop > "$WORK/overlay.prop"
log "原厂指纹: $(grep -m1 '^ro.build.fingerprint=' "$WORK/overlay.prop" | cut -d= -f2)"

# 2. overlay:system/build.prop 缺的 key 要补(GSI 没有裸 ro.build.fingerprint);另两份只改已有的
edit build.prop                 python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop" --add-missing
edit product/etc/build.prop     python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop"
edit system_ext/etc/build.prop  python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop"

# 3. 核对
fp=$(grep -m1 '^ro.build.fingerprint=' "$WORK/overlay.prop")
sudo grep -qxF "$fp" "$SYS/build.prop" || die "system/build.prop 里的指纹没写进去"
log "完成"
