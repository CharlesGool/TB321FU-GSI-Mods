# 去掉 Mystic 的 permissiver(early-init 里 setenforce 0),换成 early-init 单次 setenforce 1。
# 配合 selinux/kernel-enforcing(内核命令行 enforcing=1),内核从一开始就是 Enforcing,这里写 1 时值没变,不产生翻转。
remove system/etc/init/permissiver.rc system/bin/permissiver.sh
(( REMOVED > 0 )) || log "(底包没有 permissiver,跳过)"
put "$MOD/files/init.enforce.rc" etc/init/init.enforce.rc 0644 0:0 u:object_r:system_file:s0
