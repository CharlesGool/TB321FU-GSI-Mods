#!/system/bin/sh
# 字体包的开机保护(由 init.herald-font.rc 的两个一次性服务调用):
#   boot  post-fs-data(system_server 之前)同步跑:
#         上次留下了 boot_try(= 选了字体包但开机没走到 sys.boot_completed)→ 自动撤回 active,把包名记进 reverted;
#         否则 active 存在就先放一个 boot_try,等开机走完再由 ok 删掉。再把 active 存一份 boot_active,给 status 判断要不要重启。
#   ok    sys.boot_completed=1 以后跑:删 boot_try。
# 结果写 dmesg,前缀 herald-font:。
ROOT=${HERALD_FONT_ROOT:-/data/fonts/herald}
KMSG=${HERALD_FONT_KMSG:-/dev/kmsg}
log() { echo "herald-font: $*" > "$KMSG" 2>/dev/null; }

case "${1:-}" in
  boot)
    [ -d "$ROOT" ] || exit 0
    if [ -f "$ROOT/boot_try" ]; then
        if [ -f "$ROOT/active" ]; then
            tr -d '\r\n' < "$ROOT/active" > "$ROOT/reverted"
            rm -f "$ROOT/active"
            log "上次开机没走完,字体包 $(cat "$ROOT/reverted") 已撤回"
        fi
        rm -f "$ROOT/boot_try"
    elif [ -f "$ROOT/active" ]; then
        : > "$ROOT/boot_try"
    fi
    if [ -f "$ROOT/active" ]; then cp -f "$ROOT/active" "$ROOT/boot_active"; else rm -f "$ROOT/boot_active"; fi
    ;;
  ok)
    rm -f "$ROOT/boot_try"
    ;;
esac
exit 0
