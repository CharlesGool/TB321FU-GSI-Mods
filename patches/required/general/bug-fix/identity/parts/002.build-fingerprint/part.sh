# 指纹和 build 描述符。两种来源,由 ID_KEEP_GSI_OS_VERSION 选:
#   =0(默认):从原厂固件(STOCK_SYSTEM_IMG,可选 STOCK_VENDOR_IMG)现取整条指纹 + build 描述符 + 版本字段,
#              overlay 进三份 build.prop(机型伪装成原厂、系统版本也跟原厂)。ap3a/bp1a 用这条。
#   =1:保留 GSI 自带的安卓版本(不谎报底包版本),只把 GSI 指纹里的 brand/product/device 段换成本机型,
#        版本段(release/id/incremental)和 ro.build.version.* / security_patch 全部保留 GSI 的。CP3A 用这条
#        (原厂是 ZUI A15、底包是 Pixel 官方 A17,现取会把版本谎报成 15)。详见本目录 README「保留 GSI 版本」。
need_file build.prop
need_file product/etc/build.prop
need_file system_ext/etc/build.prop

if [[ ${ID_KEEP_GSI_OS_VERSION:-0} == 1 ]]; then
    # 保留 GSI 版本:从 GSI 自带 system/build.prop 读指纹,只换机型身份段,不碰版本字段。
    : "${ID_BRAND:?}" "${ID_NAME:?}" "${ID_DEVICE:?}"
    sudo cat "$SYS/build.prop" > "$WORK/gsi_system.prop"
    ID_BRAND=$ID_BRAND ID_NAME=$ID_NAME ID_DEVICE=$ID_DEVICE \
        python3 -I "$MOD/gsi_overlay.py" "$WORK/gsi_system.prop" > "$WORK/overlay.prop"
    log "保留 GSI 安卓版本; 机型伪装后指纹: $(grep -m1 '^ro.build.fingerprint=' "$WORK/overlay.prop" | cut -d= -f2)"
else
    # 从原厂镜像读 build.prop(换固件后自动跟着变)
    need_input STOCK_SYSTEM_IMG
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
fi

# overlay:system/build.prop 缺的 key 要补(GSI 没有裸 ro.build.fingerprint);另两份只改已有的
edit build.prop                 python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop" --add-missing
edit product/etc/build.prop     python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop"
edit system_ext/etc/build.prop  python3 -I "$TOOLKIT/lib/propedit.py" overlay "$WORK/overlay.prop"

# 核对
fp=$(grep -m1 '^ro.build.fingerprint=' "$WORK/overlay.prop")
sudo grep -qxF "$fp" "$SYS/build.prop" || die "system/build.prop 里的指纹没写进去"
log "完成"
