#!/system/bin/sh
# tango/kernel-module 的诊断(开机完成 30 秒后跑一次,herald 域)。
# V78:init 在 early-init 的 insmod 没加载上 tango32.ko,原因看不到(shell 读不了内核日志)。
# V79:post-fs-data 里再 insmod 一次 + 保留 32 位 ABI → 开机动画放到一半整机重启(怀疑:那次 insmod 成功了,32 位 zygote 一用 /dev/tango32 内核就崩)。
# 所以这里只在开机完成之后才动手,而且先把"要 insmod 了"写盘再 insmod:要是 insmod 本身把内核搞崩,下次开机看 diag.txt 最后一行就知道。
# 32 位 ABI 不在这个模块里声明(tango/zygote32 关着),所以模块加载上也不会有 32 位进程自动去用它。
KO=/system/etc/tango/tango32.ko
D=/metadata/tango_log
mkdir -p "$D" 2>/dev/null
OUT=$D/diag.txt
# 上次如果是内核崩溃重启,崩溃现场在 pstore(RAM 里,热重启保留)。先拷出来,shell 读不了 /sys/fs/pstore
if ls /sys/fs/pstore/* >/dev/null 2>&1; then
    rm -rf "$D/pstore"; mkdir -p "$D/pstore"
    cp /sys/fs/pstore/* "$D/pstore/" 2>/dev/null; chmod 0755 "$D/pstore"; chmod 0644 "$D/pstore"/* 2>/dev/null
fi
PENDING=$D/insmod_pending       # insmod 前建、insmod 返回后删;开机时还在 = 上次 insmod 让内核崩了
w() { echo "$*" >> "$OUT"; sync; }
if [ -e "$PENDING" ]; then
    # 上次的 diag.txt 留作证据,这次不再碰模块,免得每次开机都崩一次
    cp -f "$OUT" "$D/diag_crash.txt" 2>/dev/null; chmod 0644 "$D/diag_crash.txt" 2>/dev/null
    echo "== $(date) 上次开机在 insmod 时整机重启(insmod 让内核崩了),证据在 diag_crash.txt;这次不再 insmod。要重试:删掉 $PENDING" > "$OUT"
    chmod 0644 "$OUT" 2>/dev/null; exit 0
fi
: > "$OUT"; chmod 0644 "$OUT" 2>/dev/null
w "== $(date) uname=$(uname -r)"
w "-- post-fs-data 的 tango_load(insmod)之后:/proc/modules 里 tango32: $(grep -c '^tango32 ' /proc/modules)  /dev/tango32: $(ls /dev/tango32 2>&1)"
w "-- 内核日志(开机以来,tango / insmod / module / symbol / init 命令失败):"
dmesg 2>&1 | grep -iE 'tango|insmod|Unknown symbol|disagrees|module.*(fail|invalid|verif|sig)|Command .* failed' | tail -n 120 >> "$OUT"; sync
if [ -e /dev/tango32 ]; then w "== 结果:开机时已经加载上了,不再 insmod"; exit 0; fi
w "-- 现在以 herald 域(root,全部 capability,SELinux permissive)再 insmod 一次。若之后整机重启,说明 insmod 本身让内核崩了:"
: > "$PENDING"; sync
insmod "$KO" >> "$OUT" 2>&1; _rc=$?; rm -f "$PENDING"; w "insmod 退出码 $_rc"
sleep 1
w "-- 之后:/proc/modules: $(grep '^tango32 ' /proc/modules)  /dev/tango32: $(ls -lZ /dev/tango32 2>&1)"
w "-- insmod 之后的内核日志:"
dmesg 2>&1 | grep -iE 'tango|insmod|Unknown symbol|disagrees|module' | tail -n 40 >> "$OUT"; sync
w "== 结束"
exit 0
