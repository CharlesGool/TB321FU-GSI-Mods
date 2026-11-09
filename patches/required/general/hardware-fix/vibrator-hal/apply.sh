# vibrator-hal:装 tb321fu-vibrator(IVibratorManager/default)的三件套:二进制 + init rc + VINTF 声明。
# 三件必须一起装:只有 VINTF 声明没有服务,system_server 会一直等它,开机卡在动画。
# 二进制是 files/ 里的预编译件(src/build.sh 用 NDK 编);REBUILD_VIBRATOR=1 且设了 NDK 时现编。
require_mod required/general/herald-core
BIN=$MOD/files/tb321fu-vibrator
if [[ ${REBUILD_VIBRATOR:-0} == 1 ]]; then
    [[ -n ${NDK:-} ]] || die "REBUILD_VIBRATOR=1 需要设 NDK(NDK 根目录)"
    bash "$MOD/src/build.sh" "$WORK/tb321fu-vibrator" | sed 's/^/    /'
    BIN=$WORK/tb321fu-vibrator
fi
[[ -f $BIN ]] || die "缺 $BIN(先跑 NDK=... $MOD/src/build.sh)"
head -c 20 "$BIN" | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46020101.\{22\}b700' || die "$BIN 不是 aarch64 ELF"
# init 要能 search herald_payload 目录才 exec 得到二进制(test-v2.2 卡开机的原因)
cil_append "vibrator-hal: init 进 herald_payload 目录" "$MOD/init-exec.cil"
put "$BIN" etc/herald_payload/bin/tb321fu-vibrator 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tb321fu-vibrator.rc" etc/init/tb321fu-vibrator.rc 0644 0:0 u:object_r:system_file:s0
put "$MOD/files/tb321fu-vibrator.xml" etc/vintf/manifest/tb321fu-vibrator.xml 0644 0:0 u:object_r:system_file:s0
log "tb321fu-vibrator $(sha256sum "$BIN" | cut -c1-12)…;IVibratorManager/default 已声明"
