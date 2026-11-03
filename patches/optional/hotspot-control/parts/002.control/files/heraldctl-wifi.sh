# hotspot-control/002.control 的 heraldctl 插件(装在 /system/etc/heraldctl.d/wifi.sh)。用到 heraldctl 的 send、die、$TMPF。
# 命令:wifi(热点覆盖项)、hotspot(热点开关)。这些原来是 heraldctl 内置的,拆出来时一行没改。
heraldctl_help_wifi() {
  cat <<'EOT'
Wi-Fi 热点
  wifi show                     列出所有覆盖项 + 热点运行状态 + 系统热点设置(sys_* 行)
  wifi status                   cmd wifi status
  wifi set 键=值 [键=值 ...]    写覆盖项; 值留空(如 ssid=)= 删除该项, 沿用系统设置
  wifi clear [all]              清除通用覆盖项(all 连 6GHz/国家码一起清)
  hotspot start <ssid> <open|wpa2|wpa3|wpa3_transition> [密码] [-b 2|5|6|any]
  hotspot start-system          用系统「热点」设置里保存的名称/密码/安全类型/频段起热点
  hotspot stop
  hotspot status                热点开关状态(hotspot=on|off、频率、带宽)

  wifi set 的键(也可写完整名 herald_xxx):
    ch=6G信道  bw=-1|2|3|4|6|11(自动/20/40/80/160/320)  be=0|1(Wi-Fi 7)  country=DE|US|NONE
    ssid= pass= sec=0|1|2|3(开放/WPA2/WPA2+3/WPA3)  band=1|2|4|7(2.4/5/6/全部)  apbw=2|3|4|6(20/40/80/160MHz,2.4G/5G 的热点带宽)  hidden=0|1
    maxclients=N  autoshut=0|1  timeout=分钟  clientctl=0|1  macrand=0|1|2
  覆盖项在热点下次开启时生效(关掉再开); country 要重启。
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_wifi"

wkey() {
  case "$1" in
    ch|channel)  echo herald_6g_channel ;;
    bw)          echo herald_6g_bw ;;
    be)          echo herald_6g_be ;;
    country)     echo herald_wifi_country ;;
    ssid)        echo herald_ap_ssid ;;
    pass)        echo herald_ap_pass ;;
    sec)         echo herald_ap_sec ;;
    band)        echo herald_ap_band ;;
    apbw)        echo herald_ap_bw ;;
    hidden)      echo herald_ap_hidden ;;
    maxclients)  echo herald_ap_maxclients ;;
    autoshut)    echo herald_ap_autoshut ;;
    timeout)     echo herald_ap_timeout_min ;;
    clientctl)   echo herald_ap_clientctl ;;
    macrand)     echo herald_ap_macrand ;;
    herald_*)       echo "$1" ;;
    *)           return 1 ;;
  esac
}
AP_KEYS="herald_ap_ssid herald_ap_pass herald_ap_sec herald_ap_band herald_ap_bw herald_ap_hidden herald_ap_maxclients herald_ap_autoshut herald_ap_timeout_min herald_ap_clientctl herald_ap_macrand"
G6_KEYS="herald_6g_channel herald_6g_bw herald_6g_be herald_wifi_country"
heraldctl_cmd_wifi() {
    s=$1; [ $# -gt 0 ] && shift
    case "$s" in
      show)
        for k in $G6_KEYS $AP_KEYS; do
          v=$(settings get global "$k" 2>&1)
          [ "$v" = null ] && v="(未设置)"
          printf '%-20s %s\n' "$k" "$v"
        done
        echo "----"
        send wifi_get ;;
      status) send wifi_status ;;
      set)
        [ $# -ge 1 ] || die "用法: heraldctl wifi set 键=值 [键=值 ...]"
        : > "$TMPF"
        for kv in "$@"; do
          case "$kv" in *=*) ;; *) die "参数要写成 键=值: $kv" ;; esac
          k=$(wkey "${kv%%=*}") || die "不认识的键: ${kv%%=*}(heraldctl help 看列表)"
          printf '%s=%s\n' "$k" "${kv#*=}" >> "$TMPF"
        done
        send wifi_put "$TMPF" ;;
      clear)
        keys=$AP_KEYS; [ "$1" = all ] && keys="$AP_KEYS $G6_KEYS"
        : > "$TMPF"
        for k in $keys; do printf '%s=\n' "$k" >> "$TMPF"; done
        send wifi_put "$TMPF" ;;
      *) die "wifi 子命令: show status set clear" ;;
    esac
}
heraldctl_cmd_hotspot() {
    s=$1; [ $# -gt 0 ] && shift
    case "$s" in
      start) [ $# -ge 2 ] || die "用法: heraldctl hotspot start <ssid> <open|wpa2|wpa3|wpa3_transition> [密码] [-b 2|5|6|any]"
             send "hotspot_start $*" ;;
      stop)  send hotspot_stop ;;
      start-system) send hotspot_start_system ;;
      status) send hotspot_status ;;
      *)     die "hotspot 子命令: start start-system stop status" ;;
    esac
}
