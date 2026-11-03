# tango/zygote32 的 heraldctl 插件(装在 /system/etc/heraldctl.d/tango.sh)。用到 heraldctl 的 send。
heraldctl_help_tango() {
  cat <<'EOT'
32 位(Tango)
  tango status                  模块、32 位 ABI、是否回退到纯 64 位及原因
  tango retry                   清掉回退标记,下次开机重新带 32 位(要重启)
  tango off                     下次开机起按纯 64 位(要重启)
  tango logs                    把保险日志/崩溃现场导出到 /data/local/tmp/tango_log(然后 adb pull 该目录)
  tango zygote32 start|stop     回退状态下手动起/停 32 位 zygote(隔离测试,可能触发整机重启)
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_tango"
heraldctl_cmd_tango() { send "tango $*"; }
