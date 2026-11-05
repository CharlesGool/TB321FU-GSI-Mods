# 导航栏隐藏的控制:给 herald broker 加 navbar 命令(hide/show/status)和导航模式守护,给 heraldctl 加 navbar 子命令。
# 靠 herald-core 的插件机制,所以必须排在 herald-core 后面。三个 overlay 模块是它控制的对象(navbar/overlay-*)。
put "$MOD/files/navbar.sh"        etc/herald_payload/plugins/navbar.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-navbar.sh" etc/heraldctl.d/navbar.sh            0644 0:0 u:object_r:system_file:s0
