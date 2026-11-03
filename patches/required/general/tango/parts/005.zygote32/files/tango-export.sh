#!/system/bin/sh
# 把 /metadata/tango_log(保险日志、崩溃现场 pstore_*、翻译器日志)复制到 /data/local/tmp/tango_log,标签改成 shell 可读,
# 测试方不用 root、不用 rexec,直接 `adb pull /data/local/tmp/tango_log` 就能拿到。herald 域(root,permissive)跑。
# 另外把本次开机的 pstore(上次崩溃现场)也直接拷一份,万一 /metadata 那份丢了还有。
S=/metadata/tango_log
T=/data/local/tmp/tango_log
mkdir -p "$T" 2>/dev/null || exit 0
cp -rf "$S"/. "$T"/ 2>/dev/null
# 翻译器日志名里有冒号(ISO 时间),Windows 上 adb pull 会失败:导出的副本把冒号换成 -
for _f in "$T"/tango-*:*; do [ -e "$_f" ] || continue; mv -f "$_f" "$(echo "$_f" | tr ':' '-')" 2>/dev/null; done
if ls /sys/fs/pstore/* >/dev/null 2>&1; then mkdir -p "$T/pstore_now"; cp -f /sys/fs/pstore/* "$T/pstore_now/" 2>/dev/null; fi
{ echo "== $(date) uname=$(uname -r) boot_reason_last=$(getprop sys.boot.reason.last)"; echo "module=$(grep -c '^tango32 ' /proc/modules) dev=$([ -e /dev/tango32 ] && echo yes || echo no) abilist32=$(getprop ro.product.cpu.abilist32) zygote32=$(getprop tango.zygote32) fallback=$(getprop tango.fallback) svc=$(getprop init.svc.zygote_secondary)"; } > "$T/export-info.txt" 2>/dev/null
chown -R 2000:2000 "$T" 2>/dev/null
chmod -R u+rwX,go+rX "$T" 2>/dev/null
chcon -R u:object_r:shell_data_file:s0 "$T" 2>/dev/null
echo "$T"
exit 0
