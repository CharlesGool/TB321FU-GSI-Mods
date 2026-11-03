# app-backup 的 broker 插件(装在 /system/etc/herald_payload/plugins/app-backup.sh,由 herald-start.sh source)。
# 把一个应用的 apk(含 split)和数据备份到指定目录,或从那里还原。重活交给 herald-backup.sh 在后台跑,这里只管参数检查、任务状态和备份目录的查看。
# 用到 herald-start.sh 的 blog、$STATE。
#   backup [status]                              默认目录、备份个数、最近一次任务
#   backup dest [目录]                            看 / 设默认备份目录(默认 /sdcard/HeraldBackup)
#   backup app <包名> [目录] [--no-apk] [--no-data] [--ext]   备份(后台跑,回 job 号)
#   backup restore <包名> [目录] [--reinstall]    还原(应用没装就先装 apk;--reinstall 强制重装)
#   backup list [目录]                           目录里有哪些备份
#   backup delete <包名> [目录]                   删某个应用的备份
#   backup job [号]                              任务状态(不给号 = 最近一个)
# 目录规则:绝对路径,只能在 /sdcard/、/storage/、/data/media/、/data/local/tmp/、/mnt/media_rw/ 下,只允许 ASCII 的字母数字和 . _ - + @ = , : %,不含 ..。
# 一次只跑一个任务。只做用户 0。
BK_STATE=${HERALD_BK_STATE:-$STATE}
BK_CONF=$BK_STATE/backup.conf
BK_JOBS=$BK_STATE/backup-jobs
BK_WORKER=${HERALD_BK_WORKER:-/system/etc/herald_payload/herald-backup.sh}
BK_SH=${HERALD_BK_SH:-/system/bin/sh}
BK_DEFAULT=${HERALD_BK_DEFAULT:-/sdcard/HeraldBackup}
BK_ROOTS=${HERALD_BK_ROOTS:-"/sdcard/ /storage/ /data/media/ /data/local/tmp/ /mnt/media_rw/"}

herald_bk_pkgok() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; }
herald_bk_destok() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in *..*) return 1 ;; esac
  printf '%s' "$1" | grep -q '[^A-Za-z0-9._/+@=,:%-]' && return 1
  for _br in $BK_ROOTS; do case "$1/" in "$_br"*) return 0 ;; esac; done
  return 1
}
herald_bk_dest() {                                         # 默认目录(设过的 > 内置)
  _bd=""; [ -f "$BK_CONF" ] && _bd=$(sed -n 's/^dest=//p' "$BK_CONF" | tail -1)
  echo "${_bd:-$BK_DEFAULT}"
}
herald_bk_resolve() {                                      # $1 用户给的目录(可空)→ BK_D;不合法返回 1
  BK_D=${1:-$(herald_bk_dest)}
  BK_D=${BK_D%/}
  herald_bk_destok "$BK_D"
}
herald_bk_mget() { sed -n "s/^$2=//p" "$1/backup.meta" 2>/dev/null | tail -1; }
herald_bk_lastjob() { ls -1 "$BK_JOBS" 2>/dev/null | grep -v '\.new$' | sort | tail -1; }
herald_bk_jobstate() {                                     # $1 job 号;running 但进程已不在 = 判为 failed
  _jf=$BK_JOBS/$1
  [ -f "$_jf" ] || { echo "err 没有这个任务: $1"; return; }
  _js=$(sed -n 's/^state=//p' "$_jf"); _jp=$(sed -n 's/^pid=//p' "$_jf")
  _jt=$(sed -n 's/^t=//p' "$_jf"); _jt=${_jt:-0}
  if [ "$_js" = running ] && [ -n "$_jp" ] && ! kill -0 "$_jp" 2>/dev/null; then _js=failed; _jm="任务进程已退出,没有完成"
  elif [ "$_js" = running ] && [ -z "$_jp" ] && [ $(( $(date +%s) - _jt )) -gt 30 ]; then _js=failed; _jm="任务没有启动起来"
  else _jm=$(sed -n 's/^msg=//p' "$_jf"); fi
  echo "ok job $1"
  echo "state=$_js"; echo "op=$(sed -n 's/^op=//p' "$_jf")"; echo "pkg=$(sed -n 's/^pkg=//p' "$_jf")"; echo "msg=$_jm"
}
herald_bk_busy() {
  [ -d "$BK_JOBS" ] || return 1
  for _jf in "$BK_JOBS"/*; do
    [ -f "$_jf" ] || continue
    [ "$(sed -n 's/^state=//p' "$_jf")" = running ] || continue
    _jp=$(sed -n 's/^pid=//p' "$_jf")
    [ -n "$_jp" ] && kill -0 "$_jp" 2>/dev/null && return 0
  done
  return 1
}
herald_bk_start() {                                        # $1 backup|restore $2 包名 $3 目录 后面是 flags
  _bop=$1; _bpk=$2; _bdir=$3; shift 3
  herald_bk_busy && { echo "err 已有任务在跑,等它结束(backup job)"; return; }
  mkdir -p "$BK_JOBS" 2>/dev/null
  _bid=$(date +%s)$$
  printf 'state=running\nop=%s\npkg=%s\npid=\nt=%s\nmsg=已排队\n' "$_bop" "$_bpk" "$(date +%s)" > "$BK_JOBS/$_bid"
  blog "backup: $_bop $_bpk $_bdir"
  if [ -n "${HERALD_BK_SYNC:-}" ]; then
    HERALD_BK_JOB="$BK_JOBS/$_bid" $BK_SH "$BK_WORKER" "$_bop" "$_bpk" "$_bdir" "$@" >/dev/null 2>&1
  else
    ( HERALD_BK_JOB="$BK_JOBS/$_bid" $BK_SH "$BK_WORKER" "$_bop" "$_bpk" "$_bdir" "$@" >/dev/null 2>&1 </dev/null & )
  fi
  echo "ok backup $_bop $_bpk 已开始 job=$_bid"
}
herald_bk_parse() {                                        # 把参数分成 flags / 目录 / 包名:BK_PKG BK_ARGDIR BK_FLAGS;非法返回 1(BK_ERR 带原因)
  BK_PKG=""; BK_ARGDIR=""; BK_FLAGS=""; BK_ERR=""
  for _ba in "$@"; do
    case "$_ba" in
      --no-apk) BK_FLAGS="$BK_FLAGS noapk" ;;
      --no-data) BK_FLAGS="$BK_FLAGS nodata" ;;
      --ext) BK_FLAGS="$BK_FLAGS ext" ;;
      --reinstall) BK_FLAGS="$BK_FLAGS reinstall" ;;
      --*) BK_ERR="不认识的选项 $_ba"; return 1 ;;
      /*) [ -z "$BK_ARGDIR" ] || { BK_ERR="目录给了两个"; return 1; }; BK_ARGDIR=$_ba ;;
      *) [ -z "$BK_PKG" ] || { BK_ERR="多余的参数 $_ba"; return 1; }; BK_PKG=$_ba ;;
    esac
  done
  return 0
}

heraldp_backup_sub_status() {
  herald_bk_resolve "" || true
  _bn=0
  if [ -d "$BK_D" ]; then for _bp in "$BK_D"/*; do [ -f "$_bp/backup.meta" ] && _bn=$((_bn + 1)); done; fi
  echo "ok 备份"
  echo "dest=$(herald_bk_dest)"
  echo "backups=$_bn"
  _bj=$(herald_bk_lastjob)
  if [ -n "$_bj" ]; then echo "last_job=$_bj"; herald_bk_jobstate "$_bj" | sed -n 's/^state=/last_state=/p'; fi
  if herald_bk_busy; then echo "busy=1"; else echo "busy=0"; fi
  return 0
}
heraldp_backup_sub_dest() {
  if [ -z "${1:-}" ]; then echo "ok backup dest"; echo "dest=$(herald_bk_dest)"; return; fi
  herald_bk_resolve "$1" || { echo "err 目录不合法(绝对路径,在 $BK_ROOTS 下,只许 ASCII 字母数字 . _ - + @ = , : %,不含 ..)"; return; }
  { [ -f "$BK_CONF" ] && grep -v '^dest=' "$BK_CONF"; echo "dest=$BK_D"; } > "$BK_CONF.new" 2>/dev/null
  mv -f "$BK_CONF.new" "$BK_CONF" 2>/dev/null || { echo "err 写配置失败"; return; }
  echo "ok backup dest $BK_D"
}
heraldp_backup_sub_app() {
  herald_bk_parse "$@" || { echo "err $BK_ERR"; return; }
  herald_bk_pkgok "$BK_PKG" || { echo "err 用法: backup app <包名> [目录] [--no-apk] [--no-data] [--ext]"; return; }
  herald_bk_resolve "$BK_ARGDIR" || { echo "err 目录不合法: ${BK_ARGDIR:-$BK_D}"; return; }
  case "$BK_FLAGS" in *noapk*nodata*|*nodata*noapk*) echo "err --no-apk 和 --no-data 同时给就没东西可备份"; return ;; esac
  # shellcheck disable=SC2086
  herald_bk_start backup "$BK_PKG" "$BK_D" $BK_FLAGS
}
heraldp_backup_sub_restore() {
  herald_bk_parse "$@" || { echo "err $BK_ERR"; return; }
  herald_bk_pkgok "$BK_PKG" || { echo "err 用法: backup restore <包名> [目录] [--reinstall]"; return; }
  herald_bk_resolve "$BK_ARGDIR" || { echo "err 目录不合法: ${BK_ARGDIR:-$BK_D}"; return; }
  [ -f "$BK_D/$BK_PKG/backup.meta" ] || { echo "err 没找到备份: $BK_D/$BK_PKG"; return; }
  # shellcheck disable=SC2086
  herald_bk_start restore "$BK_PKG" "$BK_D" $BK_FLAGS
}
heraldp_backup_sub_list() {
  herald_bk_resolve "${1:-}" || { echo "err 目录不合法"; return; }
  echo "ok backup list dest=$BK_D"
  if [ -d "$BK_D" ]; then
    for _bp in "$BK_D"/*; do
      [ -f "$_bp/backup.meta" ] || continue
      echo "app=$(herald_bk_mget "$_bp" pkg) version=$(herald_bk_mget "$_bp" versionName) code=$(herald_bk_mget "$_bp" versionCode) time=$(herald_bk_mget "$_bp" time) apk=$(herald_bk_mget "$_bp" apk) data=$(herald_bk_mget "$_bp" data) ext=$(herald_bk_mget "$_bp" ext) kb=$(du -sk "$_bp" 2>/dev/null | cut -f1)"
    done
  fi
  return 0
}
heraldp_backup_sub_delete() {
  herald_bk_parse "$@" || { echo "err $BK_ERR"; return; }
  herald_bk_pkgok "$BK_PKG" || { echo "err 用法: backup delete <包名> [目录]"; return; }
  herald_bk_resolve "$BK_ARGDIR" || { echo "err 目录不合法"; return; }
  [ -f "$BK_D/$BK_PKG/backup.meta" ] || { echo "ok backup delete $BK_PKG(本来就没有)"; return; }
  herald_bk_busy && { echo "err 有任务在跑,等它结束"; return; }
  rm -rf "${BK_D:?}/${BK_PKG:?}"; blog "backup: delete $BK_PKG"
  echo "ok backup delete $BK_PKG"
}
heraldp_backup_sub_job() {
  _bj=${1:-$(herald_bk_lastjob)}
  [ -n "$_bj" ] || { echo "err 还没有任务"; return; }
  case "$_bj" in *[!0-9]*) echo "err 任务号是数字"; return ;; esac
  herald_bk_jobstate "$_bj"
}

heraldp_cmd_backup() {
  set -f; set -- $1; set +f
  _sub=${1:-status}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err backup 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_backup_sub_$_sub" >/dev/null 2>&1; then "heraldp_backup_sub_$_sub" "$@"
  else echo "err backup 没有子命令 $_sub"; fi
}
