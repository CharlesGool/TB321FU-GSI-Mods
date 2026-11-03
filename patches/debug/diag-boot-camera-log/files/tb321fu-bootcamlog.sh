#!/system/bin/sh
# diag-boot-camera-log:开机前 150 秒的内核日志和相机相关 logcat 存到 /data/local/tmp/tb321fu-bootlog/(shell 可读)。
# 内核日志是环形缓冲,开机两分钟后相机驱动探测传感器的那几行就被冲掉了,事后用 dmesg 抓不到,所以开机时就开始记。
O=/data/local/tmp/tb321fu-bootlog
mkdir -p "$O"; chmod 0755 "$O"
rm -f "$O/kmsg.txt" "$O/logcat.txt"
( /system/bin/timeout 150 /system/bin/dmesg -w > "$O/kmsg.txt" 2>&1; chmod 0644 "$O/kmsg.txt" ) &
( /system/bin/timeout 150 /system/bin/logcat -b all -v threadtime -e 'CamX|CHIUSECASE|[Cc]amera|[Ss]ensor|[Pp]robe|macro' > "$O/logcat.txt" 2>&1
  chmod 0644 "$O/logcat.txt" ) &
sleep 1; chmod 0644 "$O"/*.txt 2>/dev/null
wait
