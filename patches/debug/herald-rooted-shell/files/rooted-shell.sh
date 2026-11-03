# rooted-shell 的 broker 插件(装在 /system/etc/herald_payload/plugins/rooted-shell.sh,由 broker source)。
# 命令 rsh:以 broker 的身份(root,herald 域)用 sh -c 跑一整条命令,支持管道、重定向、&&、变量。和 rexec 的区别:没有白名单、没有敏感路径限制。
# 为了不能被随手滥用:
#   - 只接受命令行通道(adb shell heraldctl),配对的前端 App 一律拒绝;
#   - 默认关,`rsh on [分钟]` 打开(默认 15,最多 60),到点自动关;
#   - 每条命令(原文)和结果码都写 heraldctl log;单条 60 秒超时,输出最多 256KB;broker 运行期间不处理别的请求。
# 变量 $STATE $W $CH 和函数 blog 来自 herald-start.sh。
RS_UNTIL=$STATE/rsh_until
RS_MAXOUT=262144

rs_enabled() {
  [ -f "$RS_UNTIL" ] || return 1
  _su=$(cat "$RS_UNTIL" 2>/dev/null); case "$_su" in ""|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$_su" ]
}
heraldp_cmd_rsh() {
  _arg=$1
  if [ "$CH" != sh ]; then echo "err rsh 只接受命令行(adb shell heraldctl rsh …)"; blog "rsh 拒绝: App 通道"; return 0; fi
  case "$_arg" in
    on|"on "*)
      _m=${_arg#on}; _m=${_m# }; [ -n "$_m" ] || _m=15
      case "$_m" in *[!0-9]*|"") echo "err rsh on 的分钟数要是整数(1-60)"; return 0 ;; esac
      [ "$_m" -ge 1 ] && [ "$_m" -le 60 ] || { echo "err rsh on 的分钟数要在 1-60"; return 0; }
      echo $(( $(date +%s) + _m * 60 )) > "$RS_UNTIL"; chmod 0600 "$RS_UNTIL" 2>/dev/null
      blog "rsh 打开 ${_m} 分钟"; echo "ok rsh on ${_m}min" ;;
    off) rm -f "$RS_UNTIL"; blog "rsh 关闭"; echo "ok rsh off" ;;
    status) if rs_enabled; then echo "ok rsh on remaining=$(( $(cat "$RS_UNTIL") - $(date +%s) ))s"; else echo "ok rsh off"; fi ;;
    "") echo "err rsh 用法: rsh on [分钟] | off | status | <命令>" ;;
    *) rs_enabled || { echo "err rsh 没打开(先 heraldctl rsh on [分钟])"; return 0; }
       blog "rsh: $_arg"
       _to=""; [ -x /system/bin/timeout ] && _to="/system/bin/timeout 60"
       ( unset LD_LIBRARY_PATH; cd /; PATH=/system/bin:/system/xbin:/vendor/bin:/system/etc/herald_payload/bin:$PATH
         $_to /system/bin/sh -c "$_arg" >"$W/herald_rs" 2>&1 </dev/null ); _rc=$?
       blog "rsh rc=$_rc"
       echo "ok rsh rc=$_rc"
       head -c "$RS_MAXOUT" "$W/herald_rs" 2>/dev/null
       [ "$(wc -c < "$W/herald_rs" 2>/dev/null)" -gt "$RS_MAXOUT" ] && echo "[输出超过 $RS_MAXOUT 字节,已截断]"
       rm -f "$W/herald_rs" ;;
  esac
  return 0
}
