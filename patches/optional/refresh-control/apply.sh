require_mod required/general/herald-core
# 刷新率调节:给 herald broker 加 refresh 命令(status/modes/set/range/auto),给 heraldctl 加 refresh 子命令。
# 靠 herald-core 的插件机制,所以必须排在 herald-core 后面;optional/refresh-auto-switch 要求它在前面。
put "$MOD/files/refresh-rate.sh"          etc/herald_payload/plugins/refresh-rate.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-refresh-rate.sh"   etc/heraldctl.d/refresh-rate.sh            0644 0:0 u:object_r:system_file:s0
