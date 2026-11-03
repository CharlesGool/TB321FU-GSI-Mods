# 字体包管理:给 herald broker 加 font 命令(装包、选用、撤回),给 heraldctl 加 font 子命令;
# 开机 post-fs-data 做"选了包但开机没走完就自动撤回"的保护。靠 herald-core 的插件机制和 herald 域,必须排在它后面。
# 钩子本身由 custom-font/hook 装;不装它,选了包也没有可见效果。
put "$MOD/files/font-control.sh"   etc/herald_payload/plugins/font-control.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/herald-font.sh"       etc/herald_payload/herald-font.sh             0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/init.herald-font.rc"  etc/init/init.herald-font.rc               0644 0:0 u:object_r:system_file:s0
put "$MOD/files/heraldctl-font.sh"    etc/heraldctl.d/font.sh                    0644 0:0 u:object_r:system_file:s0
