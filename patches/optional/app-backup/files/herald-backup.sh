#!/system/bin/sh
# App 备份 / 还原的干活脚本(由 app-backup 插件在后台起,root,herald 域)。
#   herald-backup.sh backup <包名> <目标目录> [noapk] [nodata] [ext]
#   herald-backup.sh restore <包名> <来源目录> [reinstall]
# 备份放在 <目录>/<包名>/ 下:
#   backup.meta   key=value:pkg、versionName、versionCode、uid、time、apk(N|system|none)、data(0|1)、de(0|1)、ext(0|1)、splits
#   apk/          base.apk 和各 split(系统自带且没被更新过的应用不拷 apk,只备份数据)
#   data.tar      /data/user/0/<包名>(不含 cache、code_cache)
#   data_de.tar   /data/user_de/0/<包名>
#   ext.tar       /sdcard/Android/data/<包名>(带 ext 才有)
# 先写到 <包名>.partial,成功后再换名,所以备份中途失败不会毁掉上一份备份。
# 状态写到 $HERALD_BK_JOB 指的文件(state=running|done|failed、op、pkg、msg),给插件的 backup job 读。
# 只做用户 0。所有外部命令和目录都能用环境变量换,给测试用。
PM=${HERALD_BK_PM:-pm}
AM=${HERALD_BK_AM:-am}
DUMPSYS=${HERALD_BK_DUMPSYS:-dumpsys}
RESTORECON=${HERALD_BK_RESTORECON:-restorecon}
CE=${HERALD_BK_CE:-/data/user/0}
DE=${HERALD_BK_DE:-/data/user_de/0}
EXT=${HERALD_BK_EXT:-/sdcard/Android/data}
JOBF=${HERALD_BK_JOB:-/dev/null}
KMSG=${HERALD_BK_KMSG:-/dev/kmsg}

log() { echo "herald-backup: $*" > "$KMSG" 2>/dev/null; }
jset() { printf 'state=%s\nop=%s\npkg=%s\npid=%s\nmsg=%s\n' "$1" "$OP" "$PKG" "$$" "$2" > "$JOBF.new" 2>/dev/null && mv -f "$JOBF.new" "$JOBF" 2>/dev/null; }
fail() { jset failed "$1"; log "FAIL $OP $PKG: $1"; exit 1; }
pkgok() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; }
sysapk() { case "$1" in /system/*|/product/*|/vendor/*|/system_ext/*|/apex/*|/odm/*) return 0 ;; esac; return 1; }
paths_of() { $PM path "$PKG" 2>/dev/null | sed -n 's/^package://p'; }
meta_get() { sed -n "s/^$1=//p" "$SRC/backup.meta" | tail -1; }
pack_dir() {                                            # <输出 tar> <父目录>:打包 <父目录>/$PKG,跳过 cache 和 code_cache(不用 --exclude,各家 tar 都认)
  _o=$1; _p=$2
  set --
  for _f in "$_p/$PKG"/* "$_p/$PKG"/.[!.]* "$_p/$PKG"/..?*; do
    [ -e "$_f" ] || [ -L "$_f" ] || continue
    case "${_f##*/}" in cache|code_cache) continue ;; esac
    set -- "$@" "$PKG/${_f##*/}"
  done
  [ $# -gt 0 ] || set -- "$PKG"
  tar -cf "$_o" -C "$_p" "$@"
}
wipe_contents() {                                       # 清空目录里的内容(目录本身留着,属主标签不变)
  _d=$1
  [ -d "$_d" ] || return 0
  for _f in "$_d"/* "$_d"/.[!.]* "$_d"/..?*; do
    [ -e "$_f" ] || [ -L "$_f" ] || continue
    rm -rf "${_f:?}"
  done
}

OP=${1:-}; PKG=${2:-}; ARG3=${3:-}
if [ $# -ge 3 ]; then shift 3; else set --; fi
FLAGS=" $* "
has() { case "$FLAGS" in *" $1 "*) return 0 ;; esac; return 1; }

pkgok "$PKG" || fail "包名不合法"
[ -n "$ARG3" ] || fail "缺目录"
jset running "开始"

do_backup() {
  DEST=$ARG3
  [ -n "$(paths_of)" ] || fail "没有安装这个应用"
  OUT=$DEST/$PKG; PART=$DEST/$PKG.partial
  rm -rf "${PART:?}"; mkdir -p "$PART/apk" || fail "建不了目录 $PART"
  apk=none; nsplit=0
  if ! has noapk; then
    for p in $(paths_of); do
      if sysapk "$p"; then apk=system; continue; fi
      cp "$p" "$PART/apk/" || fail "拷 apk 失败: $p"
      nsplit=$((nsplit + 1)); apk=$nsplit
    done
  fi
  rmdir "$PART/apk" 2>/dev/null
  data=0; de=0; ext=0
  $AM force-stop "$PKG" >/dev/null 2>&1
  uid=$(stat -c %u "$CE/$PKG" 2>/dev/null)
  if ! has nodata; then
    if [ -d "$CE/$PKG" ]; then
      pack_dir "$PART/data.tar" "$CE" || fail "打包 $CE/$PKG 失败"
      data=1
    fi
    if [ -d "$DE/$PKG" ]; then
      pack_dir "$PART/data_de.tar" "$DE" || fail "打包 $DE/$PKG 失败"
      de=1
    fi
    if has ext && [ -d "$EXT/$PKG" ]; then
      tar -cf "$PART/ext.tar" -C "$EXT" "$PKG" || fail "打包 $EXT/$PKG 失败"
      ext=1
    fi
  fi
  [ "$apk" != none ] || [ "$data$de$ext" != 000 ] || fail "没有可备份的内容(apk 和数据都没有)"
  vn=$($DUMPSYS package "$PKG" 2>/dev/null | sed -n 's/^ *versionName=//p' | head -1)
  vc=$($DUMPSYS package "$PKG" 2>/dev/null | sed -n 's/^ *versionCode=\([0-9]*\).*/\1/p' | head -1)
  {
    echo "pkg=$PKG"; echo "versionName=$vn"; echo "versionCode=$vc"; echo "uid=$uid"; echo "time=$(date +%s)"
    echo "apk=$apk"; echo "data=$data"; echo "de=$de"; echo "ext=$ext"; echo "user=0"
  } > "$PART/backup.meta" || fail "写 backup.meta 失败"
  rm -rf "${OUT:?}.old"
  [ -d "$OUT" ] && { mv "$OUT" "$OUT.old" || fail "换不掉旧备份"; }
  mv "$PART" "$OUT" || { [ -d "$OUT.old" ] && mv "$OUT.old" "$OUT"; fail "换名失败"; }
  rm -rf "${OUT:?}.old"
  sz=$(du -sk "$OUT" 2>/dev/null | cut -f1)
  jset done "apk=$apk data=$data de=$de ext=$ext kb=${sz:-0}"
  log "ok backup $PKG apk=$apk data=$data de=$de ext=$ext"
}

install_apks() {
  set -- "$SRC"/apk/*.apk
  [ -e "$1" ] || return 1
  if [ $# -eq 1 ]; then
    $PM install -r -d "$1" >/dev/null 2>&1
  else
    _out=$($PM install-create -r -d 2>&1) || return 1
    _sid=$(printf '%s\n' "$_out" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
    [ -n "$_sid" ] || return 1
    for _f in "$@"; do
      $PM install-write "$_sid" "${_f##*/}" "$_f" >/dev/null 2>&1 || { $PM install-abandon "$_sid" >/dev/null 2>&1; return 1; }
    done
    $PM install-commit "$_sid" >/dev/null 2>&1
  fi
}

restore_tar() {   # <tar 文件> <目标父目录>
  [ -f "$1" ] || return 0
  tar -tf "$1" >/dev/null 2>&1 || fail "备份文件损坏: ${1##*/}"
  _name=$(tar -tf "$1" 2>/dev/null | head -1 | sed 's|/.*||')
  [ "$_name" = "$PKG" ] || fail "${1##*/} 里的顶层目录不是 $PKG"
  if [ -d "$2/$PKG" ]; then _own=$(stat -c %u:%g "$2/$PKG" 2>/dev/null)
  else _own=$(stat -c %u:%g "$2" 2>/dev/null); mkdir -p "$2/$PKG"; fi
  wipe_contents "$2/$PKG"
  tar -xf "$1" -C "$2" || fail "解包 ${1##*/} 失败"
  [ -z "$_own" ] || chown -R "$_own" "$2/$PKG"
  $RESTORECON -RF "$2/$PKG" >/dev/null 2>&1
}

do_restore() {
  SRC=$ARG3/$PKG
  [ -f "$SRC/backup.meta" ] || fail "没找到备份: $SRC"
  [ "$(meta_get pkg)" = "$PKG" ] || fail "backup.meta 里的包名对不上"
  if [ -z "$(paths_of)" ] || has reinstall; then
    if [ "$(meta_get apk)" = none ] || [ "$(meta_get apk)" = system ]; then
      [ -n "$(paths_of)" ] || fail "应用没装,备份里也没有 apk"
    else
      install_apks || fail "安装 apk 失败(签名不一致?已装的版本更高?)"
    fi
  fi
  [ -n "$(paths_of)" ] || fail "安装后仍找不到应用"
  $AM force-stop "$PKG" >/dev/null 2>&1
  restore_tar "$SRC/data.tar" "$CE"
  restore_tar "$SRC/data_de.tar" "$DE"
  restore_tar "$SRC/ext.tar" "$EXT"
  jset done "已还原 apk=$(meta_get apk) data=$(meta_get data) de=$(meta_get de) ext=$(meta_get ext)"
  log "ok restore $PKG"
}

case "$OP" in
  backup) do_backup ;;
  restore) do_restore ;;
  *) fail "未知操作 $OP" ;;
esac
exit 0
