# App 备份 / 还原:给 herald broker 加 backup 命令(参数检查、任务状态、备份目录查看),给 heraldctl 加 backup 子命令;
# 重活由 herald-backup.sh 在后台跑(tar + pm + restorecon)。靠 herald-core 的插件机制和 herald 域,必须排在它后面。
require_mod required/general/herald-core
put "$MOD/files/app-backup.sh"     etc/herald_payload/plugins/app-backup.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/herald-backup.sh"     etc/herald_payload/herald-backup.sh         0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-backup.sh"  etc/heraldctl.d/backup.sh                0644 0:0 u:object_r:system_file:s0
