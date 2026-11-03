# 状态栏网速显示的控制命令:给 herald broker 加 netspeed 命令,给 heraldctl 加 netspeed 子命令。
# 靠 herald-core 的插件机制,必须排在它后面。网速本身由 statusbar-netspeed/display 画;不装它,这里的开关写了也没有可见效果。
put "$MOD/files/speed-control.sh"     etc/herald_payload/plugins/speed-control.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-netspeed.sh"   etc/heraldctl.d/netspeed.sh                 0644 0:0 u:object_r:system_file:s0
