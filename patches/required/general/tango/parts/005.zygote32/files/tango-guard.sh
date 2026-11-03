#!/system/bin/sh
# tango/zygote32 的开机保险(post-fs-data,exec_start,先于 zygote-start;herald 域)。
# 历史:V78 模块没加载 → 32 位 zygote SIGILL,卡第二屏;V79 模块加载上、32 位 zygote 跑起来约 8 秒后整机硬重启(原因待 pstore);
#       V82 同样现象。真因后来定位在联想 WALT 的 32 位自检 BUG(见下面第 4 步),walt.panic_on_walt_bug=0 关掉就稳了。
#
# 稳定性/崩溃检测(pstore 现场、fallback、booting 稳定窗口、检测到可能崩就 resetprop 撤掉 32 位):
#   开发阶段很有用,但 32 位在本机已证实稳定后它只会误伤 —— 开机 120 秒内只要重启(哪怕是手动重启)就被当成
#   "32 位崩溃"而回退,回退用 resetprop 改 ro.product.cpu.abilist*,会在属性区留下被检测到的 prop 修改痕迹。
#   所以这整套检测默认不跑(ENFORCE=0),只留让 32 位能跑的必要步骤(关 WALT、加载模块、置 tango.zygote32=1)。
#   要在开发时把整套检测/回退开回来:建 /metadata/tango_log/guard_enforce,或 setprop persist.tango.guard_enforce 1。
#
# ENFORCE=1 时的完整规则(状态文件都在 /metadata/tango_log,shell 能读,卡开机也能取):
#   1. 先把 /sys/fs/pstore(上次内核崩溃的现场,热重启保留)拷到 pstore_<时间>/,旧翻译器日志只留最近 30 个。
#   2. fallback 文件在 → 这次按纯 64 位开机(粘滞,直到 `heraldctl tango retry`)。
#   3. booting 文件在 → 上次带 32 位开机没撑到"稳定"(开机完成后 120 秒)就重启了 → 写 fallback,按纯 64 位开机。
#   4./5. 关不掉 WALT-BUG / 模块没加载 → 这次按纯 64 位开机。
#   6. 都不是 → 建 booting,保留 32 位,置 tango.zygote32=1(开机完成 120 秒后 tango_stable 删掉 booting)。
# "按纯 64 位开机" = resetprop 把 abilist 改成 arm64-v8a、删掉 abilist32,置 tango.fallback=1,不置 tango.zygote32。
RP=/system/etc/herald_payload/bin/resetprop
KO=/system/etc/tango/tango32.ko
D=/metadata/tango_log
mkdir -p "$D" 2>/dev/null
OUT=$D/guard.txt
FB=$D/fallback
BOOTING=$D/booting
VER=$(getprop ro.tb321fu.mod_version)
# 稳定性/崩溃检测总开关,默认关(见文件头)。
ENFORCE=0
[ -e "$D/guard_enforce" ] && ENFORCE=1
[ "$(getprop persist.tango.guard_enforce)" = 1 ] && ENFORCE=1
log() { echo "$*" >> "$OUT"; sync; }
# guard.txt 轮换:上一次开机的留作 guard.prev.txt(V881 真机:带 32 位那次的记录被下一次开机覆盖了)
[ -e "$OUT" ] && cp -f "$OUT" "$D/guard.prev.txt" 2>/dev/null
: > "$OUT"; chmod 0644 "$OUT" "$D/guard.prev.txt" 2>/dev/null
log "== $(date) ver=$VER ro.zygote=$(getprop ro.zygote) abilist32=$(getprop ro.product.cpu.abilist32) enforce=$ENFORCE boot_reason_last=$(getprop sys.boot.reason.last)"

fallback() {
    log "== 结果:按纯 64 位开机,原因:$1"
    if [ ! -x "$RP" ]; then log "   没有 $RP,撤不掉 32 位 ABI(会卡开机)"; exit 0; fi
    "$RP" -n ro.product.cpu.abilist arm64-v8a >> "$OUT" 2>&1
    "$RP" --delete ro.product.cpu.abilist32 >> "$OUT" 2>&1 || "$RP" -n ro.product.cpu.abilist32 "" >> "$OUT" 2>&1
    setprop tango.fallback 1
    log "   abilist=$(getprop ro.product.cpu.abilist) abilist32=$(getprop ro.product.cpu.abilist32)"
    sh /system/etc/tango/tango-export.sh >/dev/null 2>&1
    exit 0
}

# ===== 稳定性/崩溃检测(默认关;ENFORCE=1 才整块执行)=====
if [ "$ENFORCE" = 1 ]; then
    # 标记文件第一行是写它的版本号;版本对不上(刷了新版本)就当不存在(V881 真机:旧版本留下的 booting 让新版本第一次开机就回退)
    for _m in "$FB" "$BOOTING"; do
        if [ -e "$_m" ] && [ "$(head -n 1 "$_m" 2>/dev/null)" != "ver=$VER" ]; then log "-- 丢弃别的版本留下的 $(basename "$_m")($(head -n 1 "$_m" 2>/dev/null))"; rm -f "$_m"; fi
    done
    # 1. 崩溃现场 + 日志清理
    if ls /sys/fs/pstore/* >/dev/null 2>&1; then
        _p=$D/pstore_$(date +%Y%m%d-%H%M%S); mkdir -p "$_p"
        cp /sys/fs/pstore/* "$_p/" 2>/dev/null; chmod 0755 "$_p"; chmod 0644 "$_p"/* 2>/dev/null
        log "-- pstore 有内容,已拷到 $_p:$(ls "$_p" | tr '\n' ' ')"
    fi
    ls -t "$D"/tango-*.log 2>/dev/null | tail -n +31 | while read -r _f; do rm -f "$_f"; done
    # 2./3. 崩溃保护
    [ -e "$FB" ] && fallback "fallback 文件在($(tail -n 1 "$FB" 2>/dev/null));要重试 32 位:heraldctl tango retry 后重启"
    if [ -e "$BOOTING" ]; then
        { echo "ver=$VER"; echo "上次带 32 位开机($(tail -n 1 "$BOOTING" 2>/dev/null))没撑到开机完成后 120 秒"; } > "$FB"; chmod 0644 "$FB"; sync
        rm -f "$BOOTING"
        fallback "上次带 32 位开机没稳定就重启了(崩溃现场看上面的 pstore_*)"
    fi
else
    log "-- 稳定性/崩溃检测已禁用(ENFORCE=0):不碰 pstore/fallback/booting,不 resetprop。开发要开:建 $D/guard_enforce"
    # 之前某次 ENFORCE=1 留下的粘滞 fallback 别挡着:禁用检测时清掉,保证带 32 位开机
    [ -e "$FB" ] && { rm -f "$FB"; log "   清掉旧的 fallback 粘滞标记"; }
fi

# ===== 让 32 位能跑的必要步骤(始终执行;检测关掉时失败只记日志、继续)=====
# 4. WALT 调度器的"32 位任务必须在 32 位核上"自检(V882 真机 console-ramoops:walt.c BUG)。
#    联想 vendor_boot 的 sched-walt.ko 在 android_rvh_set_task_cpu 里:任务带 TIF_32BIT 且目标核不在 system_32bit_el0_cpumask()
#    → WALT-BUG → BUG()。这台没有 32 位核、掩码为空,tango32.ko 把 TIF_32BIT 临时置上去调 compat_ioctl 时,任务一睡眠/迁移就必死。
#    由 sysctl walt.panic_on_walt_bug 控制(魔数 0x4544de00 | 标志位),写 0 整套检查跳过。写不进去就不该放行 32 位。
WB=/proc/sys/walt/panic_on_walt_bug
if [ -e "$WB" ]; then
    _old=$(cat "$WB" 2>/dev/null); echo 0 > "$WB" 2>>"$OUT"; _new=$(cat "$WB" 2>/dev/null)
    log "-- walt.panic_on_walt_bug: $_old -> $_new"
    if [ "$_new" != 0 ]; then
        [ "$ENFORCE" = 1 ] && fallback "关不掉 WALT-BUG(panic_on_walt_bug=$_new),带 32 位必崩,不放行"
        log "-- 警告:WALT-BUG 没关掉(=$_new),检测已禁用仍放行 32 位(可能崩)"
    fi
else
    log "-- 没有 $WB(sched-walt 不是模块或路径不同),按原样继续"
fi

# 5. 模块
if [ ! -e /dev/tango32 ]; then
    log "-- /dev/tango32 不存在,insmod:"; insmod "$KO" >> "$OUT" 2>&1; log "insmod 退出码 $?"
    _i=0; while [ ! -e /dev/tango32 ] && [ "$_i" -lt 20 ]; do sleep 0.1; _i=$((_i + 1)); done
fi
log "-- /proc/modules: $(grep '^tango32 ' /proc/modules)"
if [ ! -e /dev/tango32 ]; then
    [ "$ENFORCE" = 1 ] && fallback "tango32.ko 没加载上"
    log "-- 警告:tango32.ko 没加载,检测已禁用仍继续(32 位可能不可用)"
fi

# 6. 带 32 位开机
[ "$ENFORCE" = 1 ] && { echo "ver=$VER"; date; } > "$BOOTING" 2>/dev/null && chmod 0644 "$BOOTING" 2>/dev/null && sync
setprop tango.zygote32 1
log "== 结果:保留 32 位 ABI,tango.zygote32=1(zygote-start 起 zygote_secondary)$([ "$ENFORCE" = 1 ] && echo ';开机完成 120 秒后算稳定')"
sh /system/etc/tango/tango-export.sh >/dev/null 2>&1
exit 0
