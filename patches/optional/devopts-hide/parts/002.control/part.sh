# 按 App 隐藏的控制命令:给 herald broker 加 hide 命令(规则管理),给 heraldctl 加 hide 子命令;
# 开机 post-fs-data 把规则写成 zygote 读的配置文件。靠 herald-core 的插件机制和 herald 域,必须排在它后面。
# 钩子本身由 devopts-hide/hook 装;不装它,这里的规则写了也没有可见效果。
put "$MOD/files/hide-control.sh"       etc/herald_payload/plugins/hide-control.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/herald-devopts-hide.sh"   etc/herald_payload/herald-devopts-hide.sh     0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/init.herald-devhide.rc"   etc/init/init.herald-devhide.rc            0644 0:0 u:object_r:system_file:s0
put "$MOD/files/heraldctl-hide.sh"        etc/heraldctl.d/hide.sh                    0644 0:0 u:object_r:system_file:s0
