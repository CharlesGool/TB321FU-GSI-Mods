# 自适应刷新率:按前台应用 / 电量自动换刷新率。依赖 optional/refresh-control()(它提供 refresh 命令和 herald_ref_* 函数)。
require_mod required/general/herald-core
require_mod optional/refresh-control
put "$MOD/files/adaptive-refresh.sh"          etc/herald_payload/plugins/adaptive-refresh.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-adaptive-refresh.sh"   etc/heraldctl.d/adaptive-refresh.sh            0644 0:0 u:object_r:system_file:s0
