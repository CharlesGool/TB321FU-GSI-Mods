# 把 tango32.ko 装进系统,开机 insmod;ueventd 给 /dev/tango32 开 0666(所有翻译进程都要读写)。
need_input TANGO32_KO
: "${TANGO_KERNEL_RELEASE:?device.conf 没设 TANGO_KERNEL_RELEASE}"
need_file etc/ueventd.rc
need_tool python3
# .ko 必须是 aarch64 ELF relocatable,vermagic 第一段 = 目标内核发布串
python3 -I - "$TANGO32_KO" "$TANGO_KERNEL_RELEASE" <<'PY' || die "$TANGO32_KO 不合格(不是 aarch64 的 .ko,或 vermagic 不是 $TANGO_KERNEL_RELEASE)"
import sys,struct,re
d=open(sys.argv[1],'rb').read()
ok = d[:4]==b'\x7fELF' and d[4]==2 and struct.unpack('<H',d[16:18])[0]==1 and struct.unpack('<H',d[18:20])[0]==0xb7
m = re.search(rb'vermagic=(\S+)', d)
print('vermagic:', m.group(1).decode() if m else None, file=sys.stderr)
sys.exit(0 if ok and m and m.group(1).decode()==sys.argv[2] else 1)
PY
put_dir etc/tango 0755 0:0 u:object_r:system_file:s0
put "$TANGO32_KO" etc/tango/tango32.ko 0644 0:0 u:object_r:system_file:s0
put "$MOD/files/tango-insmod.sh" etc/tango/tango-insmod.sh 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tango-module.rc" etc/init/tango-module.rc 0644 0:0 u:object_r:system_file:s0
# 诊断:开机完成 30 秒后,把 init 的 insmod 结果和内核日志写到 /metadata/tango_log/diag.txt,没加载上就再 insmod 一次(V80)
put "$MOD/files/tango-diag.sh" etc/tango/tango-diag.sh 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tango-diag.rc" etc/init/tango-diag.rc 0644 0:0 u:object_r:system_file:s0
if sudo grep -q '^/dev/tango32[[:space:]]' "$SYS/etc/ueventd.rc"; then
    log "(ueventd.rc 已含 /dev/tango32)"
else
    printf '\n# tango/kernel-module\n/dev/tango32 0666 system system\n' | append etc/ueventd.rc >/dev/null
    log "+ ueventd.rc: /dev/tango32 0666"
fi
