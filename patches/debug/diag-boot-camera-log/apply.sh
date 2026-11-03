# 诊断:开机前 150 秒的内核日志 + 相机相关 logcat 存到 /data/local/tmp/tb321fu-bootlog/,查相机驱动开机时探测到哪几个传感器用。
# 借 herald-core 的 herald 域(permissive)跑,所以要它在前面。默认不打(MODS_OFF),查问题时 WITH=diag-boot-camera-log。
require_mod required/general/herald-core
put "$MOD/files/tb321fu-bootcamlog.sh" etc/tb321fu-bootcamlog.sh 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/tb321fu-bootcamlog.rc" etc/init/tb321fu-bootcamlog.rc 0644 0:0 u:object_r:system_file:s0
