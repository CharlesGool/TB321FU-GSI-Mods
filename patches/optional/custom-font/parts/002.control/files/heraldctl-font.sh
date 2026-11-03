# custom-font/control 的 heraldctl 插件(装在 /system/etc/heraldctl.d/font.sh)。用到 heraldctl 的 send、die。
heraldctl_help_font() {
  cat <<'EOT'
自定义系统字体(需要装了 custom-font/hook;切换后重启生效)
  font [status]                  当前字体包、包数量、要不要重启
  font list                      所有包和各自是否完整
  font install <zip|目录> [名字]  装包(来源在 /data/local/tmp/ 或 /sdcard/ 下;zip 顶层要有 font_fallback.xml)
  font use <名字>                选用某个包
  font reset                     回到系统字体
  font remove <名字>             删包(正在用的不让删)
  font check <名字>              检查包是否完整
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_font"

heraldctl_cmd_font() {
  send "font $*"
}
