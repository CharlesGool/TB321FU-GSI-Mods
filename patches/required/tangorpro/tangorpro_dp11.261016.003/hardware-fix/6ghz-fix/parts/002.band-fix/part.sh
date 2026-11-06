# band-fix:设置里选 6GHz 时把热点固定在 6GHz 频段(信道交给驱动自动选,不固定带宽和 802.11be)。
# herald_6g_channel / herald_6g_bw / herald_6g_be 设了才套用(信道 1–233 且 (信道-1)%4==0;带宽 -1/2/3/4/6/11;be 非 0 开 802.11be)。
# 贡献者:只把补丁登记给 wifi-apex-assemble,自己不动 APEX。能不能开出 6GHz 热点由 Wi-Fi 资源开关(原厂 overlay 或
# optional/hotspot-6ghz-unlock)决定;设置页没有 6GHz 选项时,补丁里的判断("配置里只有一个频段键且含 6GHz 位")永远不满足,等于不起作用。
: "${WIFI_APEX_FILE:?device.conf / conf.d/wifi.conf 没设 WIFI_APEX_FILE}"
need_file "$WIFI_APEX_FILE"
contrib_add wifi-service-jar "$MOD/patches/01-SoftApManager-6ghz.diff" \
    'const-string v6, "herald_6g_channel"'
