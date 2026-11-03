# readonly-shell 的 heraldctl 插件(装在 /system/etc/heraldctl.d/readonly-shell.sh,由 heraldctl source)。用到 heraldctl 的 send、die。
heraldctl_help_rexec() {
  cat <<'HELP'
只读 root 查看(分析系统用;默认关)
  rexec on [分钟]               打开(默认 30 分钟,最多 120),到点自动关
  rexec off | rexec status
  rexec <命令> [参数…]          以 root 跑一条查看类命令,输出原样打印,退出码同命令
    允许: cat ls stat find grep head tail wc cut sort readlink realpath file md5sum sha1sum sha256sum od hexdump xxd strings
          lsattr df du id uname uptime ps lsof lsmod pidof getenforce getprop ss netstat which nproc free vmstat mount(无参数)
          date +格式  dmesg(不清缓冲)  logcat -d  dumpsys  settings get|list  service list|check  pm list|path|dump
          cmd overlay|package|wifi 的只读子命令  ip addr|route|link|neigh|rule  wm size|density
    不经 shell: 不能用 ; | & < > $ ` ( ) { } \ ' "(要过滤就在电脑上 findstr);参数按空格切分,不支持带空格的参数
    敏感位置(keystore/keybox、/data/adb、OMK 数据和通道、Wi-Fi/蓝牙密钥、锁屏凭据、账户库、块设备、内核内存)一律拒绝
HELP
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_rexec"

heraldctl_cmd_rexec() {
  [ $# -ge 1 ] || die "用法: heraldctl rexec on [分钟] | off | status | <命令> [参数…]"
  case "$1" in
    on|off|status) send "rexec $*"; return $? ;;
  esac
  # 回包可能很大(dmesg、logcat):落到文件再处理,不放进变量(mksh 没有内建 printf,大参数会 "Argument list too long")
  rf=$TMPF.rx
  send "rexec $*" > "$rf"; src=$?
  first=$(head -1 "$rf")
  case "$first" in
    "ok rexec rc="*)
      tail -n +2 "$rf"; rm -f "$rf"
      rc=${first#ok rexec rc=}; case "$rc" in ""|*[!0-9]*) rc=1 ;; esac
      return "$rc" ;;
    *) cat "$rf"; rm -f "$rf"; return "$src" ;;
  esac
}
