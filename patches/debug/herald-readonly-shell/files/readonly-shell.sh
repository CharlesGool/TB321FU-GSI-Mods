# readonly-shell 的 broker 插件(装在 /system/etc/herald_payload/plugins/readonly-shell.sh,由 broker source)。
# 命令 rexec:以 root 身份跑一批「只读查看」类命令,用来分析系统。不是 root shell:
#   - 不经 shell 解析(禁 ; | & < > $ ` ( ) { } \ ' "),只跑下面白名单里的程序,个别程序还限制了参数;
#   - 参数里出现敏感路径(见 RX_DENY)一律拒绝,路径会先 readlink -f 解符号链接再比,递归类命令(find/grep/ls/du)不允许从敏感目录的上级开始;
#   - 命令行随时可用;配对的前端 App 要在配对时被授权(heraldctl pair <包名> --allow rexec),并且命令行打开着窗口才能执行,开关只能命令行;
#   - 默认关,`rexec on [分钟]` 打开(默认 30,最多 120),到点自动关;每条命令和拒绝原因都写 heraldctl log。
# 变量 $STATE $W $CH 和函数 blog 来自 herald-start.sh。
RX_UNTIL=$STATE/rexec_until
RX_MAXOUT=262144
RX_DENY="/data/misc/keystore /data/adb /data/local/tmp/herald /system/etc/herald_payload /data/misc/apexdata/com.android.wifi /data/misc/wifi /data/misc/vold /metadata/vold /data/misc/bluedroid /data/misc/user /data/misc_ce /data/misc_de /data/system/gatekeeper /data/system/locksettings /data/system_ce /data/system_de /dev/block /dev/mem /dev/kmem /proc/kcore /proc/kmem"

rx_enabled() {
  [ -f "$RX_UNTIL" ] || return 1
  _ru=$(cat "$RX_UNTIL" 2>/dev/null); case "$_ru" in ""|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$_ru" ]
}
# 路径是否落在敏感位置。$1=路径 $2=1 表示递归类命令(上级目录也拒绝)
rx_path_bad() {
  _p=$1; _rec=$2
  case "$_p" in /*) ;; *) _p="/$_p" ;; esac
  _r=$(readlink -f -- "$_p" 2>/dev/null); [ -n "$_r" ] || _r=$_p
  case "$_p" in */../*|*/..) [ "$_r" = "$_p" ] && return 0 ;; esac   # 解不开的 .. 不放行
  for _x in "$_p" "$_r"; do
    _x=${_x%/}
    case "$_x" in /proc/*/mem|/proc/*/task/*/mem|*/herald_token|*/herald_req|*/herald_resp) return 0 ;; esac
    for _d in $RX_DENY; do
      case "$_x" in "$_d"|"$_d"/*) return 0 ;; esac
      if [ "$_rec" = 1 ]; then case "$_d/" in "$_x"/*) return 0 ;; esac; fi
    done
  done
  return 1
}
# 参数检查:$1=命令名 $2=1 递归类。其余参数在 "$@"(用 shift 2 之后)里。返回 0 通过,否则打印原因并返回 1
rx_args_ok() {
  _name=$1; _rec=$2; shift 2
  for _a in "$@"; do
    for _d in $RX_DENY; do case "$_a" in *"$_d"*) echo "参数里有敏感路径 $_d"; return 1 ;; esac; done
    case "$_a" in
      /*) _c=$_a ;;
      -*=*) _c=${_a#*=}; case "$_c" in /*) ;; *) _c="" ;; esac ;;
      -*) _c="" ;;
      *) if [ -e "/$_a" ]; then _c=$_a; else _c=""; fi ;;
    esac
    if [ -n "$_c" ] && rx_path_bad "$_c" "$_rec"; then echo "路径 $_c 在敏感位置(或是它的上级,递归命令不允许)"; return 1; fi
  done
  return 0
}
# 逐个命令的白名单。返回 0=允许;否则打印原因返回 1。输出 REC=1 表示递归类(用全局 RX_REC 传回)
rx_allowed() {
  _n=$1; shift; RX_REC=0
  case "$_n" in
    cat|stat|readlink|realpath|file|wc|head|tail|cut|md5sum|sha1sum|sha256sum|od|hexdump|strings|lsattr|df|id|uname|uptime|whoami|ps|lsof|lsmod|pidof|getenforce|getprop|ss|netstat|which|nproc|free|vmstat) ;;
    ls) for _a in "$@"; do case "$_a" in --recursive) RX_REC=1 ;; --*) ;; -*R*) RX_REC=1 ;; esac; done ;;
    du) RX_REC=1 ;;
    grep) for _a in "$@"; do case "$_a" in --recursive|--dereference-recursive|--directories=*) RX_REC=1 ;; --*) ;; -*[dDrR]*) RX_REC=1 ;; esac; done ;;
    find) RX_REC=1
          for _a in "$@"; do case "$_a" in -exec|-execdir|-ok|-okdir|-delete|-fprint|-fprint0|-fprintf|-fls) echo "find 不允许 $_a"; return 1 ;; esac; done ;;
    sort) for _a in "$@"; do case "$_a" in -o|--output|--output=*|-o?*) echo "sort 不允许 -o"; return 1 ;; esac; done ;;
    dmesg) for _a in "$@"; do case "$_a" in --clear|--console-level) echo "dmesg 不允许清缓冲/改级别"; return 1 ;; --*) ;; -*[cCn]*) echo "dmesg 不允许清缓冲/改级别"; return 1 ;; esac; done ;;
    logcat) _d=0
            for _a in "$@"; do case "$_a" in
              -c|--clear|-G|-f|-r|-n|-P|--prune|-p|--regex=*) echo "logcat 不允许 $_a"; return 1 ;;
              -d|-g|-S|-L) _d=1 ;; esac; done
            [ $_d = 1 ] || { echo "logcat 必须带 -d(或 -g/-S/-L),否则会一直阻塞"; return 1; } ;;
    dumpsys) for _a in "$@"; do case "$_a" in set|set-*|unplug|reset|enable|disable|override|force|force-*|suspend|whitelist|add|remove|clear|start|stop|kill|crash|trigger|write|reload) echo "dumpsys 不允许 $_a(这些参数会改系统状态)"; return 1 ;; esac; done ;;
    date) for _a in "$@"; do case "$_a" in +*) ;; *) echo "date 只允许 +格式"; return 1 ;; esac; done ;;
    mount) [ $# -eq 0 ] || { echo "mount 只允许无参数(列出挂载)"; return 1; } ;;
    wm) [ $# -eq 1 ] && case "$1" in size|density) ;; *) false ;; esac || { echo "wm 只允许 size 或 density"; return 1; } ;;
    service) case "$1" in list|check) ;; *) echo "service 只允许 list/check"; return 1 ;; esac ;;
    settings) case "$1" in get|list) ;; *) echo "settings 只允许 get/list"; return 1 ;; esac ;;
    pm) case "$1" in list|path|dump|resolve-activity|get-privapp-permissions) ;; *) echo "pm 只允许 list/path/dump/resolve-activity"; return 1 ;; esac ;;
    cmd) case "$1:$2" in
           overlay:list|overlay:dump|overlay:lookup|package:list|package:path|package:dump|package:resolve-activity|wifi:status|wifi:get-country-code|wifi:list-networks|display:*get*|connectivity:*get*) ;;
           *) echo "cmd 只允许 overlay list/dump/lookup、package list/path/dump/resolve-activity、wifi status/get-country-code/list-networks"; return 1 ;; esac ;;
    ip) case "$1" in addr|a|address|route|r|link|l|neigh|n|rule) ;; *) echo "ip 只允许 addr/route/link/neigh/rule"; return 1 ;; esac
        for _a in "$@"; do case "$_a" in add|del|delete|flush|set|change|replace|append|prepend|save|restore|exec) echo "ip 不允许 $_a"; return 1 ;; esac; done ;;
    *) echo "不在白名单: $_n"; return 1 ;;
  esac
  return 0
}
rx_run() {
  _line=$1
  set -f
  case "$_line" in
    *[\;\|\&\<\>\$\`\(\)\{\}\\\'\"]*) echo "err rexec 命令行里有 shell 元字符(; | & < > \$ \` ( ) { } \\ ' \"),不经 shell 解析,请去掉"; return 1 ;;
  esac
  set -- $_line
  [ $# -ge 1 ] || { echo "err rexec 用法: rexec <命令> [参数…] | rexec on [分钟] | rexec off | rexec status"; return 1; }
  _n=$1; shift
  case "$_n" in */*) echo "err rexec 命令名不能带路径: $_n"; return 1 ;; esac
  _why=$(rx_allowed "$_n" "$@") || { echo "err rexec 拒绝: $_why"; blog "rexec 拒绝: $_line ($_why)"; return 1; }
  rx_allowed "$_n" "$@" >/dev/null; # 取 RX_REC(上面是子 shell,拿不到)
  _why=$(rx_args_ok "$_n" "$RX_REC" "$@") || { echo "err rexec 拒绝: $_why"; blog "rexec 拒绝: $_line ($_why)"; return 1; }
  _bin=/system/bin/$_n
  [ -x "$_bin" ] || { echo "err rexec 本机没有 $_bin"; return 1; }
  blog "rexec: $_line"
  _to=""; [ -x /system/bin/timeout ] && _to="/system/bin/timeout 30"
  ( unset LD_LIBRARY_PATH; cd /; $_to "$_bin" "$@" >"$W/herald_rx" 2>&1 </dev/null ); _rc=$?
  echo "ok rexec rc=$_rc"
  head -c "$RX_MAXOUT" "$W/herald_rx" 2>/dev/null
  [ "$(wc -c < "$W/herald_rx" 2>/dev/null)" -gt "$RX_MAXOUT" ] && echo "[输出超过 $RX_MAXOUT 字节,已截断]"
  rm -f "$W/herald_rx"
  return 0
}
heraldp_cmd_rexec() {
  _arg=$1
  # 通道:命令行随时可以;配对的前端 App 要同时满足 ① 配对时授权过(heraldctl pair <包名> --allow rexec)② 命令行打开着窗口。
  # 开关(on/off)只能命令行,App 只能查 status 和执行命令。
  if [ "$CH" != sh ]; then
    case " $PAIR_SCOPES " in
      *" rexec "*|*" rexec,"*|*",rexec "*|*",rexec,"*) ;;
      *) case "$PAIR_SCOPES" in rexec|rexec,*|*,rexec|*,rexec,*) ;;
           *) echo "err rexec 这个前端没有被授权(命令行 heraldctl pair <包名> --allow rexec 重新配对时授权)"; blog "rexec 拒绝: App 通道没有 rexec 授权 scopes=${PAIR_SCOPES:-none}"; return 0 ;;
         esac ;;
    esac
    case "$_arg" in on|"on "*|off) echo "err rexec 开关只能命令行(adb shell heraldctl rexec on|off),前端只能查 status 和执行命令"; blog "rexec 拒绝: App 通道不能开关"; return 0 ;; esac
  fi
  case "$_arg" in
    on|"on "*)
      _m=${_arg#on}; _m=${_m# }; [ -n "$_m" ] || _m=30
      case "$_m" in *[!0-9]*|"") echo "err rexec on 的分钟数要是整数(1-120)"; return 0 ;; esac
      [ "$_m" -ge 1 ] && [ "$_m" -le 120 ] || { echo "err rexec on 的分钟数要在 1-120"; return 0; }
      echo $(( $(date +%s) + _m * 60 )) > "$RX_UNTIL"; chmod 0600 "$RX_UNTIL" 2>/dev/null
      blog "rexec 打开 ${_m} 分钟"; echo "ok rexec on ${_m}min" ;;
    off) rm -f "$RX_UNTIL"; blog "rexec 关闭"; echo "ok rexec off" ;;
    status) if rx_enabled; then echo "ok rexec on remaining=$(( $(cat "$RX_UNTIL") - $(date +%s) ))s"; else echo "ok rexec off"; fi ;;
    *) rx_enabled || { echo "err rexec 没打开(先 heraldctl rexec on [分钟])"; return 0; }
       ( rx_run "$_arg" ) ;;
  esac
  return 0
}
