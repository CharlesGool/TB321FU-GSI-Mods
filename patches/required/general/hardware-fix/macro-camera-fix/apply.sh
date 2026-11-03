# macro-camera-fix:system/build.prop 加 ro.vendor.qti.va_aosp.support=1,和原厂 system 一样。
# 高通 vendor 用 libqti_vndfwk_detect 的 isRunningWithVendorEnhancedFramework()(= 读这一个属性)判断"system 是不是高通增强版"。
# 没有它 = 当成 GSI:相机 HAL(com.qti.chi.override)改用 lanai_gsi 的多摄配置,只报 0、1 号相机,微距(2 号)被藏掉。
need_file build.prop
prop build.prop ro.vendor.qti.va_aosp.support 1 --add
sudo grep -qx 'ro.vendor.qti.va_aosp.support=1' "$SYS/build.prop" || die "build.prop 里没写进去"
log "ro.vendor.qti.va_aosp.support=1"
