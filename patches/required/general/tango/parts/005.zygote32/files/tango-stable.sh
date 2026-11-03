#!/system/bin/sh
# 开机完成 120 秒还活着 = 带 32 位开机稳定,删掉 booting 标记(见 tango-guard.sh);顺便把日志导出到 /data/local/tmp/tango_log
sleep 120
D=/metadata/tango_log
if [ -e "$D/booting" ]; then rm -f "$D/booting"; echo "== $(date) 稳定:开机完成 120 秒,删掉 booting" >> "$D/guard.txt"; fi
sh /system/etc/tango/tango-export.sh >/dev/null 2>&1
exit 0
