# root shell:给 herald broker 加 rsh 命令(任意命令经 sh -c 以 root 跑,默认关、限时打开、只接受命令行),给 heraldctl 加 rsh 子命令。
# 照 debug/herald-readonly-shell 的插件做法,必须排在 herald-core 后面。
require_mod required/general/herald-core
put "$MOD/files/rooted-shell.sh"           etc/herald_payload/plugins/rooted-shell.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-rooted-shell.sh" etc/heraldctl.d/rooted-shell.sh            0644 0:0 u:object_r:system_file:s0
