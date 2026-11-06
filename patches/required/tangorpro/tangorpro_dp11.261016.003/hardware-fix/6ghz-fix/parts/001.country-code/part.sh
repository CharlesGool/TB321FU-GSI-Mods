# wifi-country-code:Wi-Fi 国家码改成读 Settings.Global herald_wifi_country(默认 DE)。
# 贡献者模块:只把补丁登记给 apex-assemble,自己不动 APEX。原理见 README.md。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

: "${WIFI_APEX_FILE:?device.conf / conf.d/wifi.conf 没设 WIFI_APEX_FILE}"
need_file "$WIFI_APEX_FILE"     # 底包里没有 Wi-Fi APEX 就在这里失败,不等到 assemble

contrib_add wifi-service-jar "$MOD/patches/01-WifiCountryCode.diff" \
    'const-string v1, "herald_wifi_country"'
