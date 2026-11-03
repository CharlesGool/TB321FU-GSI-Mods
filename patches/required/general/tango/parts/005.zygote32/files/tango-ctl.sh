# tango/zygote32 的 broker 插件(装在 /system/etc/herald_payload/plugins/tango.sh)。
#   tango status   32 位状态:模块、ABI、是否回退到纯 64 位及原因、保险日志
#   tango retry    删掉回退标记,下次开机重新带 32 位(要重启)
#   tango off      写回退标记,下次开机起一直按纯 64 位(要重启)
#   tango logs     把 /metadata/tango_log(保险日志、pstore 崩溃现场、翻译器日志)导出到 /data/local/tmp/tango_log,adb pull 直接取
#   tango zygote32 start|stop   手动隔离测试:在回退(纯 64 位)状态下,开机完成后再起 32 位 zygote(临时给上 abilist32),
#                  看整机重启是不是只和"32 位 zygote 跑起来"有关;system_server 不知道它,不会往它 fork app。stop 撤回。
TANGO_D=/metadata/tango_log
heraldp_cmd_tango() {
  case "$1" in
    status|"")
      echo "ok tango status"
      echo "module=$(grep -c '^tango32 ' /proc/modules)"
      echo "dev=$([ -e /dev/tango32 ] && echo yes || echo no)"
      echo "abilist32=$(getprop ro.product.cpu.abilist32)"
      echo "zygote32_allowed=$(getprop tango.zygote32)"
      echo "ro.zygote=$(getprop ro.zygote)"
      echo "uffd_gc=$(getprop ro.dalvik.vm.enable_uffd_gc)"
      echo "boot_reason_last=$(getprop sys.boot.reason.last)"
      echo "pstore_now=$(ls /sys/fs/pstore 2>/dev/null | wc -l)"
      echo "zygote32_svc=$(getprop init.svc.tango_zygote32)"
      echo "walt_panic_on_walt_bug=$(cat /proc/sys/walt/panic_on_walt_bug 2>/dev/null || echo none)"
      echo "zygote32_manual=$(getprop tango.zygote32.manual)"
      echo "updatable_crashing=$(getprop sys.init.updatable_crashing)"
      echo "fallback_now=$(getprop tango.fallback)"
      echo "fallback_sticky=$([ -e "$TANGO_D/fallback" ] && cat "$TANGO_D/fallback" || echo no)"
      echo "booting_marker=$([ -e "$TANGO_D/booting" ] && echo yes || echo no)"
      echo "pstore_dirs=$(ls -d "$TANGO_D"/pstore_* 2>/dev/null | wc -l)"
      echo "--- guard.txt"; cat "$TANGO_D/guard.txt" 2>/dev/null ;;
    retry) rm -f "$TANGO_D/fallback" "$TANGO_D/booting"; blog "tango: 清掉回退标记"; echo "ok tango retry reboot-required" ;;
    off)   echo "手动关($(date))" > "$TANGO_D/fallback"; chmod 0644 "$TANGO_D/fallback"; blog "tango: 手动回退纯 64 位"; echo "ok tango off reboot-required" ;;
    logs)  _t=$(sh /system/etc/tango/tango-export.sh 2>/dev/null); blog "tango: 日志导出到 $_t"; echo "ok tango logs $_t"; ls -la "$_t" 2>/dev/null ;;
    "zygote32 start")
      [ -e /dev/tango32 ] || { echo "err tango zygote32: /dev/tango32 不存在,先看 insmod.txt"; return; }
      if [ -e /proc/sys/walt/panic_on_walt_bug ]; then echo 0 > /proc/sys/walt/panic_on_walt_bug; [ "$(cat /proc/sys/walt/panic_on_walt_bug)" = 0 ] || { echo "err tango zygote32: 关不掉 WALT-BUG,带 32 位必崩"; return; }; fi
      _rp=/system/etc/herald_payload/bin/resetprop
      "$_rp" -n ro.product.cpu.abilist32 armeabi-v7a,armeabi; "$_rp" -n ro.product.cpu.abilist arm64-v8a,armeabi-v7a,armeabi
      { echo "== $(date) 手动起 32 位 zygote(tango zygote32 start)"; } >> "$TANGO_D/guard.txt"; sync
      setprop tango.zygote32.manual start; blog "tango: 手动起 32 位 zygote"
      sleep 3; echo "ok tango zygote32 start svc=$(getprop init.svc.tango_zygote32) abilist32=$(getprop ro.product.cpu.abilist32)" ;;
    "zygote32 stop")
      setprop tango.zygote32.manual stop; sleep 1
      _rp=/system/etc/herald_payload/bin/resetprop
      "$_rp" -n ro.product.cpu.abilist arm64-v8a; "$_rp" --delete ro.product.cpu.abilist32 2>/dev/null || "$_rp" -n ro.product.cpu.abilist32 ""
      blog "tango: 手动停 32 位 zygote"; echo "ok tango zygote32 stop svc=$(getprop init.svc.tango_zygote32)" ;;
    *)     echo "err tango 用法: tango status|retry|off|logs|zygote32 start|zygote32 stop" ;;
  esac
}
