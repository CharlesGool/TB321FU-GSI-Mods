# hotspot-overrides:热点参数(名称、密码、加密、频段、隐藏、最大连接数、自动关闭、批准连接、MAC 随机化)
# 由 Settings.Global 的 herald_ap_* 覆盖。
# 贡献者模块:只把补丁登记给 apex-assemble,自己不动 APEX。原理见 README.md。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

: "${WIFI_APEX_FILE:?device.conf / conf.d/wifi.conf 没设 WIFI_APEX_FILE}"
need_file "$WIFI_APEX_FILE"

# 两个补丁必须一起登记(02 调用 01 加的方法),所以放在同一个模块里,不能只开一半
contrib_add wifi-service-jar "$MOD/patches/01-SoftApManager-overrides.diff" \
    '.method public static heraldApplyApOverrides(Lcom/android/server/wifi/SoftApManager;)V'
contrib_add wifi-service-jar "$MOD/patches/02-IdleState-call.diff" \
    '->heraldApplyApOverrides(Lcom/android/server/wifi/SoftApManager;)V'
