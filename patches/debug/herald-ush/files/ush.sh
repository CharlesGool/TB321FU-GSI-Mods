# ush 的 broker 插件(装在 /system/etc/herald_payload/plugins/ush.sh,由 broker source)。
# 命令 ush:以 broker 身份(root,herald 域)用 sh -c 跑一整条命令,支持管道、重定向、&&、变量。
# 和 readonly-shell(rexec)的区别:没有白名单、没有敏感路径限制,也不需要先开启——装上即用,配套前端是无特权的 /system/bin/ush。
# 为了不能被随手滥用(不是安全边界):
#   - 只接受命令行通道(adb shell ush …),配对的前端 App 一律拒绝;
#   - 每条命令(原文)和退出码都写 heraldctl log(blog);
#   - 列进 HERALDP_ASYNC 后台执行,慢命令不阻塞 broker 主循环;单条 600 秒超时,输出最多 256KB。
# 变量 $CH $W 和函数 blog 来自 herald-start.sh。
USH_MAXOUT=262144

heraldp_cmd_ush() {
  _arg=$1
  if [ "$CH" != sh ]; then echo "err ush 只接受命令行(adb shell ush …)"; blog "ush 拒绝: App 通道"; return 0; fi
  [ -n "$_arg" ] || { echo "err ush 用法: ush <命令>"; return 0; }
  blog "ush: $_arg"
  _o=$W/ush.out.$$.$RANDOM.$RANDOM      # 唯一临时文件:HERALDP_ASYNC 下可能有并发,别共用固定名
  _to=""; [ -x /system/bin/timeout ] && _to="/system/bin/timeout 600"
  ( unset LD_LIBRARY_PATH; cd /; PATH=/system/bin:/system/xbin:/vendor/bin:/system/etc/herald_payload/bin:$PATH
    $_to /system/bin/sh -c "$_arg" >"$_o" 2>&1 </dev/null ); _rc=$?
  blog "ush rc=$_rc"
  echo "ok ush rc=$_rc"
  head -c "$USH_MAXOUT" "$_o" 2>/dev/null
  [ "$(wc -c < "$_o" 2>/dev/null)" -gt "$USH_MAXOUT" ] && echo "[输出超过 $USH_MAXOUT 字节,已截断]"
  rm -f "$_o"
  return 0
}
HERALDP_ASYNC="$HERALDP_ASYNC ush"
