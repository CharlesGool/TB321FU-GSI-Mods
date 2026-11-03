# perf/thermal-readout 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/perf-temps.sh)。命令本身是 perf(由 perf/node-access 转发)。
heraldctl_help_perf_temps() {
  cat <<'EOT'
  perf temps [all]                 温度:cpu / gpu / 外壳 / 电池的最大值和全机最高;all 另列所有 thermal_zone
EOT
}
