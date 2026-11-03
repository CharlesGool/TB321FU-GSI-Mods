# perf/gpu-freq 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/perf-gpu.sh)。命令本身是 perf(由 perf/node-access 转发)。
heraldctl_help_perf_gpu() {
  cat <<'EOT'
  perf gpu status                  GPU 当前/最低/最高频率、可用档位
  perf gpu set <min|max> <值>      值:Hz 数值 | NMHz | N%(不超过最高档*N% 的最大一档)| stock(出厂值)
  perf gpu reset                   恢复出厂值
EOT
}
