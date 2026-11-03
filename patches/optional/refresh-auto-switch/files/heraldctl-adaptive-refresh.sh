# optional/refresh-auto-switch 的 heraldctl 帮助(装在 /system/etc/heraldctl.d/adaptive-refresh.sh)。
# 命令本身就是 refresh(由 refresh-control 的 heraldctl 插件转发),这里只提供 heraldctl_help_refresh_adaptive,让 help 里多几行。
heraldctl_help_refresh_adaptive() {
  cat <<'EOT'
  refresh adaptive on|off|status   按场景自动换刷新率(前台应用规则 > 低电量封顶 > 默认)
  refresh default <规格>            自动模式下没有别的规则时用(规格:auto | Hz | 最小-最大)
  refresh app <包名> <规格|off>     给某个应用单独定刷新率,off 删掉规则(例 refresh app com.android.chrome 60)
  refresh apps                      列出应用规则
  refresh battery <电量%> <规格>    电量低于 N% 且没在充电时封顶(例 refresh battery 20 60);refresh battery off 取消
EOT
}
