# qs-auto-brightness:快捷设置的"自动亮度"开关(TB321FU-QSBrightness.apk,系统分区,没有桌面图标)。
# WRITE_SETTINGS 是 signature|preinstalled|appop:装在系统分区自动获得。源码在 app/,app/build-linux.sh 编。
put_dir system_ext/app/TB321FU-QSBrightness 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/TB321FU-QSBrightness.apk" system_ext/app/TB321FU-QSBrightness/TB321FU-QSBrightness.apk 0644 0:0 u:object_r:system_file:s0
