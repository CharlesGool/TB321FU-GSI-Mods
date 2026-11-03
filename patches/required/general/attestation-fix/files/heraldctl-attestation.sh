# attestation-fix 的 heraldctl 插件(装在 /system/etc/heraldctl.d/00-attestation.sh)。用到 heraldctl 的 send、die、$TMPF。
# 命令:spoof(指纹伪装)、keybox、rkp。这些原来是 heraldctl 内置的,拆出来时一行没改。
heraldctl_help_attestation() {
  cat <<'EOT'
机型伪装
  spoof get                     当前伪装配置和全局开关
  spoof list                    内建机型列表
  spoof apply <product> [b p v] 用内建机型预填(不打开全局开关); product 取 spoof list 里的名字, 如 panther_beta
  spoof set <profile.json>      写入 profile 并打开全局伪装(重启生效)
  spoof off                     关闭全局伪装(重启生效)
  spoof mode [app|global]       伪装方式:app = 只给名单里的 App 换 Build.*(默认),global = 全局改属性(重启生效)
  spoof apps [add|remove <名字>] 按 App 伪装的名单(默认 + 额外,重启生效)
  spoof patch <YYYY-MM-DD|auto> [all] 同步安全补丁日期(auto = 用当前 profile 里的日期); 不能晚于今天;
                                加 all = 连 os/vendor/boot_patchlevel 一起改(默认不动;改低会让用更高级别生成的现有密钥失效)
  spoof auto-targets [get|on|off]  inject 的自动目标发现(监听 packages.list / 遍历 /data/app 找新装 App;
                                这个特征会被某些检测器当成 KernelSU track_throne);每次重新注入后已自动关,
                                这里只是诊断/手动开关,不写配置文件,keystore2 重启后要再关一次

Keybox
  keybox state|inspector|revocation
  keybox export > keybox.xml
  keybox import <keybox.xml>

RKP 下发
  rkp issue [protocol] | rkp list | rkp import <结果id>
    protocol 不写就是 v2(真机实测本机只有 v2 能用;auto 不稳定,v1/v1-native 会报错)
EOT
}
HERALDCTL_HELP="${HERALDCTL_HELP:-} heraldctl_help_attestation"

heraldctl_cmd_spoof() {
    s=$1; [ $# -gt 0 ] && shift
    case "$s" in
      get)   send get ;;
      list)  send list ;;
      apply) send "apply $*" ;;
      off)   send disable ;;
      patch) [ -n "$1" ] || die "用法: heraldctl spoof patch <YYYY-MM-DD|auto> [all]"; case "$2" in ""|all) ;; *) die "用法: heraldctl spoof patch <YYYY-MM-DD|auto> [all]" ;; esac; send "patch $1${2:+ $2}" ;;
      set)   [ -f "$1" ] || die "用法: heraldctl spoof set <profile.json>(文件不存在: $1)"
             grep -q '"fingerprint"' "$1" || die "err $1 里没有 fingerprint 字段"
             send set "$1" ;;
      mode)  case "$1" in ""|app|global) ;; *) die "用法: heraldctl spoof mode [app|global]" ;; esac; send "spoof_mode $*" ;;
      apps)  case "$1" in ""|list) send "spoof_apps list" ;;
               add|remove) [ -n "$2" ] || die "用法: heraldctl spoof apps add|remove <进程名或包名>"; send "spoof_apps $1 $2" ;;
               *) die "用法: heraldctl spoof apps [list] | add|remove <进程名或包名>" ;; esac ;;
      auto-targets) case "$1" in
               ""|get) send auto_targets_get ;;
               on)     send "auto_targets_set 1" ;;
               off)    send "auto_targets_set 0" ;;
               *) die "用法: heraldctl spoof auto-targets [get|on|off]" ;; esac ;;
      *)     die "spoof 子命令: get list apply set off patch mode apps auto-targets" ;;
    esac
}
heraldctl_cmd_keybox() {
    s=$1; [ $# -gt 0 ] && shift
    case "$s" in
      state)      send keybox_state ;;
      inspector)  send keybox_inspector ;;
      revocation) send keybox_revocation ;;
      export)     send keybox_export ;;
      import)     [ -f "$1" ] || die "用法: heraldctl keybox import <keybox.xml>"
                  base64 "$1" | tr -d '\r\n' > "$TMPF" || die "err base64 失败"
                  send keybox_import "$TMPF" ;;
      *)          die "keybox 子命令: state inspector revocation export import" ;;
    esac
}
heraldctl_cmd_rkp() {
    s=$1; [ $# -gt 0 ] && shift
    case "$s" in
      issue)  send "rkp_issue $*" ;;
      list)   send rkp_list ;;
      import) send "rkp_import $*" ;;
      *)      die "rkp 子命令: issue list import" ;;
    esac
}
