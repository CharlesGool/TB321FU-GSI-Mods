# 只读 root 查看:给 herald broker 加 rexec 命令(白名单里的查看类命令以 root 跑,敏感路径拒绝,默认关、限时打开),给 heraldctl 加 rexec 子命令。
# 靠 herald-core 的插件机制,所以必须排在 herald-core 后面。
require_mod required/general/herald-core
put "$MOD/files/readonly-shell.sh"        etc/herald_payload/plugins/readonly-shell.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-readonly-shell.sh" etc/heraldctl.d/readonly-shell.sh            0644 0:0 u:object_r:system_file:s0
