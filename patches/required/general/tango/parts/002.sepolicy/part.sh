# Tango 要的 SELinux 策略:tango_prop / tango32_device 两个新类型,给翻译进程(zygote、app、crash_dump…)的 execmem 和 /dev/tango32 访问,
# init 挂 binfmt_misc 的权限,/dev/tango32 和 tango.* 属性的标签。
cil_append "tango/sepolicy: Tango 翻译进程" "$MOD/tango.cil"

# 属性标签:追加到 plat_property_contexts(幂等)
PC=etc/selinux/plat_property_contexts
need_file "$PC"
if sudo grep -q '^tango\.enabled[[:space:]]' "$SYS/$PC"; then
    log "(plat_property_contexts 已含 tango.*)"
else
    { echo ""; echo "# tango/sepolicy"; cat "$MOD/property_contexts"; } | append "$PC" >/dev/null
    log "+ plat_property_contexts: tango.*"
fi

fc_append "tango/sepolicy: /dev/tango32 与翻译器" <<'FC'
/dev/tango32 u:object_r:tango32_device:s0
/system_ext/bin/tango_translator u:object_r:system_lib_file:s0
/metadata/tango_log(/.*)? u:object_r:tango_log_file:s0
FC
