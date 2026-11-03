# perf/profiles 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/perf-profiles.sh)。命令本身是 perf(由 perf/node-access 转发)。
heraldctl_help_perf_profiles() {
  cat <<'EOT'
  perf profile [status]                       当前档位(powersave / balanced / performance / custom)
  perf profile powersave|balanced|performance 一键切档:省电 = CPU/GPU 最高频限到 60%;性能 = CPU 最低频抬到 40%;均衡 = 全部出厂值
EOT
}
