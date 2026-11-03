# perf/cpu-freq 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/perf-cpu.sh)。命令本身是 perf(由 perf/node-access 转发)。
heraldctl_help_perf_cpu() {
  cat <<'EOT'
  perf cpu status                         各簇当前/最低/最高频率、可用档位、调速器
  perf cpu set <簇号|all> <min|max> <值>   值:kHz 数值 | N%(不超过最高档*N% 的最大一档)| stock(出厂值)
                                          例 perf cpu set all max 70%   perf cpu set 7 max 2000000
  perf cpu governor <簇号|all> <名|stock>   调速器(可选项见 status 的 policyN_governors)
  perf cpu online <核号|all> <on|off>       核心开关(至少留一个在线)
  perf cpu reset                          全部恢复出厂值(频率、调速器、核心全开)
EOT
}
