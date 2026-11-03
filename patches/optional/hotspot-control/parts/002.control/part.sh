# 热点控制的命令:给 herald-core 的 broker 加 wifi_get / wifi_put / hotspot_* / wifi_status(覆盖项读写、热点开关、系统热点设置读取),
# 给 heraldctl 加 wifi / hotspot。靠 herald-core 的插件机制;没选核心时前面三个部分照常打(Settings 键靠 adb 或别的前端写),这部分跳过。
mod_ran required/general/herald-core || { log "没有 herald-core,跳过 heraldctl / broker 命令(Settings 键 herald_ap_* 仍可手动写)"; return 0; }
put "$MOD/files/wifi.sh"        etc/herald_payload/plugins/wifi.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-wifi.sh" etc/heraldctl.d/wifi.sh            0644 0:0 u:object_r:system_file:s0
