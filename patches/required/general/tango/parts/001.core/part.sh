# 装 Tango 翻译器 + 开机注册 binfmt_misc。让内核把 32 位 ARM ELF 交给 /system_ext/bin/tango_translator。
# 翻译器二进制来自 Tango 集成包($TANGO_PKG),不进仓库。
need_input TANGO_PKG
T=$TANGO_PKG/prebuilts/tango_translator
[[ -f $T ]] || die "集成包里没有 prebuilts/tango_translator: $T"
# aarch64 ELF:魔数 7f454c46,e_machine=0xb7(小端 b7 00),64 位(EI_CLASS=2)
python3 -I - "$T" <<'PY' || die "$T 不是 aarch64 ELF"
import sys,struct
h=open(sys.argv[1],'rb').read(20)
sys.exit(0 if h[:4]==b'\x7fELF' and h[4]==2 and struct.unpack('<H',h[18:20])[0]==0xb7 else 1)
PY
sudo test -d "$SYS/system_ext/bin" || die "底包里没有 system/system_ext/bin"
sudo test -d "$SYS/etc/init" || die "底包里没有 system/etc/init"
# 标签 system_lib_file:官方 file_contexts 就是这么定的(内核当解释器 exec 时各域都有 system_lib_file 的执行/映射权限)
put "$T" system_ext/bin/tango_translator 0755 0:2000 u:object_r:system_lib_file:s0
put "$MOD/files/tango-binfmt.rc" etc/init/tango-binfmt.rc 0644 0:0 u:object_r:system_file:s0
prop build.prop tango.enabled 1 --add
prop build.prop tango.debug "${TANGO_DEBUG:-off}" --add
if [[ ${TANGO_DEBUG:-off} != off ]]; then
    prop build.prop tango.log_dir /metadata/tango_log --add
    put "$MOD/files/tango-debug.rc" etc/init/tango-debug.rc 0644 0:0 u:object_r:system_file:s0
fi
