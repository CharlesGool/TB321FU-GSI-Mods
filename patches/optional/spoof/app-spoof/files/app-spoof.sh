# spoof/app-spoof 的 broker 插件(装在 /system/etc/herald_payload/plugins/app-spoof.sh)。用到 herald-start.sh 的 CFG、ENABLE_FLAG、blog。
#   spoof_mode                    当前选的模式和这次开机实际生效的方式
#   spoof_mode app|global         切换模式(重启生效);伪装开着时顺带按新模式重排补丁级别(要 pending/ 里 herald-start.sh 的补丁)
#   spoof_apps                    名单(默认 + 额外)
#   spoof_apps add|remove <名字>  额外名单加/减(进程名或包名,重启生效)
# 模式:app = 按 App 伪装(系统属性不动,名单里的 App 看到伪装的 Build.*);global = 开机 resetprop 全局改属性(V81 及以前的行为)。
# 模式文件不存在 = app。
ASP_DIR=/system/etc/herald_payload/app-spoof
ASP_MODE=$CFG/data/spoof_mode
ASP_EXTRA=$CFG/data/app_spoof_targets
ASP_CONF=/data/system/imitation.conf

herald_spoof_mode() { case "$(cat "$ASP_MODE" 2>/dev/null)" in global) echo global ;; *) echo app ;; esac; }
herald_asp_name_ok() { case "$1" in ""|*[!A-Za-z0-9._:]*|.*|*..*) return 1 ;; esac; return 0; }

heraldp_cmd_spoof_mode() {
  set -- $1
  set -- "${1:-}"   # broker 是 set -u:无参查询时 $1 未设会 "parameter not set"(V83 真机)
  case "$1" in
    "")
      echo "ok spoof_mode"
      echo "mode=$(herald_spoof_mode)"
      # 这次开机实际怎么生效的:有配置文件 = 按 App;没有但开关开着 = 全局;都没有 = 关
      if [ -f "$ASP_CONF" ]; then echo "effective=app"
      elif [ -f "$ENABLE_FLAG" ]; then echo "effective=global"
      else echo "effective=off"; fi ;;
    app|global)
      _old=$(herald_spoof_mode)
      echo "$1" > "$ASP_MODE"; chown 1017:1017 "$ASP_MODE" 2>/dev/null; chmod 0600 "$ASP_MODE" 2>/dev/null
      blog "spoof_mode: $_old -> $1"
      echo "ok spoof_mode $1 reboot-required"
      # 补丁级别按模式重排(app 模式全局 security_patch 保持真机,global 模式跟 profile),函数在 herald-start.sh 的补丁里
      if [ -f "$ENABLE_FLAG" ] && type herald_spoof_patch_sync >/dev/null 2>&1; then
        echo "security_patch: $(herald_spoof_patch_sync 2>&1 | head -1)"
      fi ;;
    *) echo "err spoof_mode 用法: spoof_mode [app|global]" ;;
  esac
}

heraldp_cmd_spoof_apps() {
  set -- $1
  set -- "${1:-}" "${2:-}"
  case "$1" in
    ""|list)
      echo "ok spoof_apps"
      while IFS= read -r _a; do [ -n "$_a" ] && echo "default=$_a"; done < "$ASP_DIR/targets.default"
      [ -f "$ASP_EXTRA" ] && while IFS= read -r _a; do [ -n "$_a" ] && echo "extra=$_a"; done < "$ASP_EXTRA" ;;
    add|remove)
      herald_asp_name_ok "$2" || { echo "err spoof_apps 用法: spoof_apps add|remove <进程名或包名>"; return; }
      { [ -f "$ASP_EXTRA" ] && grep -vxF "$2" "$ASP_EXTRA"; [ "$1" = add ] && echo "$2"; } > "$ASP_EXTRA.new" 2>/dev/null
      mv -f "$ASP_EXTRA.new" "$ASP_EXTRA"; chown 1017:1017 "$ASP_EXTRA" 2>/dev/null; chmod 0600 "$ASP_EXTRA" 2>/dev/null
      blog "spoof_apps: $1 $2"
      echo "ok spoof_apps $1 $2 reboot-required" ;;
    *) echo "err spoof_apps 用法: spoof_apps [list] | add|remove <进程名或包名>" ;;
  esac
}
