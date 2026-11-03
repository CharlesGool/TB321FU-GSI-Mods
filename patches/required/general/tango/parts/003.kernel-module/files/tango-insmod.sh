#!/system/bin/sh
# post-fs-data 由 init exec_start(herald 域)加载 tango32.ko,结果写 /metadata/tango_log/insmod.txt(每次开机覆盖,上一次留 insmod.prev.txt)
D=/metadata/tango_log; mkdir -p "$D" 2>/dev/null
O=$D/insmod.txt; [ -e "$O" ] && cp -f "$O" "$D/insmod.prev.txt"
{
  echo "== $(date) ver=$(getprop ro.tb321fu.mod_version) uname=$(uname -r)"
  if grep -q '^tango32 ' /proc/modules; then echo "已加载(开机更早时候)"; else
    /system/bin/insmod /system/etc/tango/tango32.ko 2>&1; echo "insmod 退出码 $?"
  fi
  _i=0; while [ ! -e /dev/tango32 ] && [ "$_i" -lt 30 ]; do sleep 0.1; _i=$((_i + 1)); done
  echo "/proc/modules: $(grep '^tango32 ' /proc/modules)"; echo "/dev/tango32: $(ls -lZ /dev/tango32 2>&1)"
} > "$O" 2>&1; chmod 0644 "$O" "$D/insmod.prev.txt" 2>/dev/null; sync
exit 0
