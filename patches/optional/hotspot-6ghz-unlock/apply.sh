# hotspot-6ghz-unlock:解锁 6GHz 热点(能力位、服务端信道列表、设置页信道列表三道门)。6GHz 频段修复和国家码在必选的 6ghz-fix 的 003.6ghz-control。
# 贡献者模块:只把补丁登记给 apex-assemble,自己不动 APEX。原理见 README.md。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

: "${WIFI_APEX_FILE:?device.conf / conf.d/wifi.conf 没设 WIFI_APEX_FILE}"
need_file "$WIFI_APEX_FILE"

# 三个补丁各自带一个回编后必须能在 smali 里 grep 到的标记
contrib_add wifi-service-jar "$MOD/patches/01-ApConfigUtil.diff" \
    'const/16 v1, 0x1bcb'
contrib_add wifi-service-jar "$MOD/patches/02-WifiServiceImpl.diff" \
    'const/16 v2, 0x1bcb'
