#!/usr/bin/env bash
# app-backup 的单元测试:插件 + 后台脚本都在临时目录里跑,pm / am / dumpsys / restorecon 用桩脚本,
# 数据目录换成临时目录(真 tar、真 cp);dash 和 busybox sh 各一遍。用法: toolkit/test-backup-plugin.sh  (不碰真机)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/patches/optional/app-backup/files
T=$(mktemp -d "${TMPDIR:-/tmp}/bktest.XXXXXX"); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "  FAIL: $*"; }
chk()  { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok; else bad "$1: 缺 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
has()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok; else bad "$1: 缺子串 '$3'"; echo "$2" | sed 's/^/      | /'; fi; }
nohas(){ if printf '%s\n' "$2" | grep -qF -- "$3"; then bad "$1: 不该有 '$3'"; else ok; fi; }

mkdir -p "$T/stub" "$T/apk"
# ---- 桩 ----
cat > "$T/stub/pm" <<'EOF'
#!/bin/sh
APPS=$BKT/apps
register() { mkdir -p "$BKT/ce/$1" "$BKT/de/$1" "$APPS/$1"; echo "package:/data/app/$1/base.apk" > "$APPS/$1/paths"; echo "$1" >> "$BKT/installed.log"; }
case "$1" in
  path) [ -f "$APPS/$2/paths" ] && cat "$APPS/$2/paths"; exit 0 ;;
  install) for a; do f=$a; done; [ -n "${PM_FAIL:-}" ] && exit 1; register "$(head -1 "$f" | sed 's/^pkg=//')"; echo "Success" ;;
  install-create) echo "Success: created install session [42]" ;;
  install-write) head -1 "$4" | sed 's/^pkg=//' > "$BKT/session"; echo "wrote $3" >> "$BKT/pm.log" ;;
  install-commit) register "$(cat "$BKT/session")"; echo "Success" ;;
  install-abandon) ;;
esac
EOF
printf '#!/bin/sh\necho "$@" >> "$BKT/am.log"\n' > "$T/stub/am"
printf '#!/bin/sh\necho "    versionCode=123 minSdk=1"\necho "    versionName=1.2.3"\n' > "$T/stub/dumpsys"
printf '#!/bin/sh\necho "$@" >> "$BKT/restorecon.log"\n' > "$T/stub/restorecon"
chmod +x "$T/stub"/*
printf 'pkg=com.example.app\nBASE\n' > "$T/apk/base.apk"; printf 'pkg=com.example.app\nSPLIT\n' > "$T/apk/split_a.apk"

setup_app() {   # 装好 com.example.app:两个 split、CE/DE/ext 数据
  rm -rf "$T/apps" "$T/ce" "$T/de" "$T/ext"
  mkdir -p "$T/apps/com.example.app" "$T/ce/com.example.app/files" "$T/ce/com.example.app/cache" "$T/de/com.example.app" "$T/ext/com.example.app"
  printf 'package:%s\npackage:%s\n' "$T/apk/base.apk" "$T/apk/split_a.apk" > "$T/apps/com.example.app/paths"
  echo secret > "$T/ce/com.example.app/files/token"; echo junk > "$T/ce/com.example.app/cache/c"; echo .hid > "$T/ce/com.example.app/.hidden"
  echo de > "$T/de/com.example.app/prefs"; echo ext > "$T/ext/com.example.app/data.bin"
  : > "$T/am.log"; : > "$T/restorecon.log"; : > "$T/installed.log"; : > "$T/pm.log"
}

run() {   # run <sh> <backup 参数串…>
  local sh=$1; shift
  {
    echo "STATE=$T/state; blog() { :; }"
    echo ". $M/app-backup.sh"
    for c in "$@"; do echo "heraldp_cmd_backup '$c'; echo"; done
  } > "$T/drv.sh"
  BKT=$T HERALD_BK_STATE=$T/state HERALD_BK_ROOTS="$T/dest/" HERALD_BK_DEFAULT=$T/dest/default HERALD_BK_WORKER=$M/herald-backup.sh HERALD_BK_SH=$sh \
    HERALD_BK_PM=$T/stub/pm HERALD_BK_AM=$T/stub/am HERALD_BK_DUMPSYS=$T/stub/dumpsys HERALD_BK_RESTORECON=$T/stub/restorecon \
    HERALD_BK_CE=$T/ce HERALD_BK_DE=$T/de HERALD_BK_EXT=$T/ext HERALD_BK_KMSG=/dev/null HERALD_BK_SYNC=${SYNC-1} $sh "$T/drv.sh" 2>&1
}
lastjob() { sed -n 's/^state=//p' "$T/state/backup-jobs/$(ls -1 "$T/state/backup-jobs" | sort | tail -1)"; }
lastmsg() { sed -n 's/^msg=//p' "$T/state/backup-jobs/$(ls -1 "$T/state/backup-jobs" | sort | tail -1)"; }

suite() {
  local sh=$1 out D=$T/dest
  echo "== $sh"; rm -rf "$T/state" "$T/dest"; mkdir -p "$T/state" "$D"; setup_app
  out=$(run "$sh" "" "status"); chk "默认 dest" "$out" "dest=$T/dest/default"; chk "默认 backups" "$out" "backups=0"; chk "默认 busy" "$out" "busy=0"
  out=$(run "$sh" "dest $D/mine" "dest"); has "dest 设置" "$out" "ok backup dest $D/mine"; chk "dest 读回" "$out" "dest=$D/mine"
  out=$(run "$sh" "dest relative" "dest /etc/x" "dest $D/../x" "dest $D/中文" "dest $D/a;b" "dest $D/a\$b")
  [ "$(printf '%s\n' "$out" | grep -c '^err 目录不合法')" = 6 ] && ok || { bad "非法目录全拒绝(期望 6)"; echo "$out" | sed 's/^/      | /'; }
  out=$(run "$sh" "dest"); chk "非法后 dest 不变" "$out" "dest=$D/mine"

  # ---- 备份 ----
  out=$(run "$sh" "app com.example.app $D --ext"); has "app 回包" "$out" "ok backup backup com.example.app 已开始 job="
  [ "$(lastjob)" = done ] && ok || { bad "备份任务应 done: $(lastjob) $(lastmsg)"; }
  B=$D/com.example.app
  [ -f "$B/apk/base.apk" ] && [ -f "$B/apk/split_a.apk" ] && ok || bad "apk 和 split 要拷进去"
  [ -f "$B/data.tar" ] && [ -f "$B/data_de.tar" ] && [ -f "$B/ext.tar" ] && ok || bad "三个 tar 要有"
  tar -tf "$B/data.tar" | grep -q 'com.example.app/files/token' && ok || bad "data.tar 要含数据"
  tar -tf "$B/data.tar" | grep -q 'com.example.app/.hidden' && ok || bad "data.tar 要含点文件"
  tar -tf "$B/data.tar" | grep -q '/cache' && bad "data.tar 不该含 cache" || ok
  meta=$(cat "$B/backup.meta"); chk "meta pkg" "$meta" "pkg=com.example.app"; chk "meta versionName" "$meta" "versionName=1.2.3"; chk "meta versionCode" "$meta" "versionCode=123"
  chk "meta apk" "$meta" "apk=2"; chk "meta data" "$meta" "data=1"; chk "meta de" "$meta" "de=1"; chk "meta ext" "$meta" "ext=1"
  grep -q 'force-stop com.example.app' "$T/am.log" && ok || bad "备份前要 force-stop"
  [ ! -e "$D/com.example.app.partial" ] && [ ! -e "$D/com.example.app.old" ] && ok || bad "不该留 .partial/.old"
  out=$(run "$sh" "list $D"); has "list" "$out" "app=com.example.app version=1.2.3 code=123"; has "list ext" "$out" "ext=1"
  out=$(run "$sh" "status" "job"); chk "status last_state" "$out" "last_state=done"; chk "job state" "$out" "state=done"; chk "job op" "$out" "op=backup"

  # 再备份一次 = 替换
  echo newer > "$T/ce/com.example.app/files/token2"; run "$sh" "app com.example.app $D" >/dev/null
  tar -tf "$B/data.tar" | grep -q token2 && ok || bad "第二次备份要替换旧的"
  [ ! -f "$B/ext.tar" ] && ok || bad "第二次没带 --ext,旧的 ext.tar 不该留"
  rm -f "$T/ce/com.example.app/files/token2"

  # ---- 选项 ----
  run "$sh" "app com.example.app $D --no-data" >/dev/null
  [ -d "$B/apk" ] && [ ! -f "$B/data.tar" ] && ok || bad "--no-data 只有 apk"
  chk "no-data meta" "$(cat "$B/backup.meta")" "data=0"
  run "$sh" "app com.example.app $D --no-apk" >/dev/null
  [ ! -d "$B/apk" ] && [ -f "$B/data.tar" ] && ok || bad "--no-apk 只有数据"
  chk "no-apk meta" "$(cat "$B/backup.meta")" "apk=none"
  out=$(run "$sh" "app com.example.app $D --no-apk --no-data"); has "两个都不要" "$out" "err --no-apk 和 --no-data"
  # 系统应用:路径在 /system 下,不拷 apk
  mkdir -p "$T/apps/com.sys.app" "$T/ce/com.sys.app"; echo "package:/system/app/Sys/Sys.apk" > "$T/apps/com.sys.app/paths"; echo d > "$T/ce/com.sys.app/f"
  run "$sh" "app com.sys.app $D" >/dev/null
  chk "系统应用 meta" "$(cat "$D/com.sys.app/backup.meta")" "apk=system"
  [ ! -d "$D/com.sys.app/apk" ] && ok || bad "系统应用不拷 apk"
  # 没装的应用
  run "$sh" "app com.nope.app $D" >/dev/null; [ "$(lastjob)" = failed ] && has "没装" "$(lastmsg)" "没有安装" || bad "没装应该 failed"
  [ ! -e "$D/com.nope.app" ] && [ ! -e "$D/com.nope.app.partial" ] && ok || bad "失败不该留目录"
  # 参数校验
  out=$(run "$sh" "app" "app bad" "app ../x" "app com.example.app /etc" "app com.example.app --zzz" "app com.example.app $D $D/x" "app a.b c.d" "frob" "restore")
  [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 9 ] && ok || { bad "非法参数全拒绝(期望 9 个 err)"; echo "$out" | sed 's/^/      | /'; }

  # ---- 还原 ----
  run "$sh" "app com.example.app $D --ext" >/dev/null
  echo changed > "$T/ce/com.example.app/files/token"; echo extra > "$T/ce/com.example.app/files/extra"; echo x > "$T/ce/com.example.app/.dot2"; echo dd > "$T/de/com.example.app/prefs"
  : > "$T/restorecon.log"; : > "$T/am.log"
  out=$(run "$sh" "restore com.example.app $D"); has "restore 回包" "$out" "ok backup restore com.example.app 已开始"
  [ "$(lastjob)" = done ] && ok || bad "还原任务应 done: $(lastmsg)"
  [ "$(cat "$T/ce/com.example.app/files/token")" = secret ] && ok || bad "数据要还原成备份时的内容"
  [ ! -e "$T/ce/com.example.app/files/extra" ] && [ ! -e "$T/ce/com.example.app/.dot2" ] && ok || bad "还原要先清掉多出来的文件(含点文件)"
  [ "$(cat "$T/de/com.example.app/prefs")" = de ] && ok || bad "DE 数据要还原"
  [ "$(cat "$T/ext/com.example.app/data.bin")" = ext ] && ok || bad "ext 数据要还原"
  grep -q -- "-RF $T/ce/com.example.app" "$T/restorecon.log" && ok || bad "要 restorecon -RF CE 目录"
  grep -q -- "-RF $T/de/com.example.app" "$T/restorecon.log" && ok || bad "要 restorecon -RF DE 目录"
  [ ! -s "$T/installed.log" ] && ok || bad "已装的应用不该重装"
  grep -q 'force-stop' "$T/am.log" && ok || bad "还原前要 force-stop"
  # 没装:先装 apk(两个 split → install-create/write/commit),再还原数据
  rm -rf "$T/apps/com.example.app" "$T/ce/com.example.app" "$T/de/com.example.app"; : > "$T/installed.log"; : > "$T/pm.log"
  run "$sh" "restore com.example.app $D" >/dev/null
  [ "$(lastjob)" = done ] && ok || bad "没装也能还原: $(lastmsg)"
  [ "$(cat "$T/installed.log")" = com.example.app ] && ok || bad "要先安装"
  [ "$(grep -c wrote "$T/pm.log")" = 2 ] && ok || bad "两个 split 都要 install-write"
  [ "$(cat "$T/ce/com.example.app/files/token")" = secret ] && ok || bad "装完要还原数据"
  # --reinstall
  : > "$T/installed.log"; run "$sh" "restore com.example.app $D --reinstall" >/dev/null
  [ "$(cat "$T/installed.log")" = com.example.app ] && ok || bad "--reinstall 要重装"
  # 安装失败
  rm -rf "$T/apps/com.example.app"; PM_FAIL=1 run "$sh" "restore com.example.app $D" >/dev/null
  # PM_FAIL 对 install-commit 不起作用,单 apk 才用 install;所以只检查任务有结论
  [ "$(lastjob)" = done ] || [ "$(lastjob)" = failed ] && ok || bad "安装路径要有结论"
  # 备份文件损坏:不动现有数据
  setup_app; run "$sh" "app com.example.app $D" >/dev/null
  echo garbage > "$B/data.tar"; echo keepme > "$T/ce/com.example.app/files/token"
  run "$sh" "restore com.example.app $D" >/dev/null
  [ "$(lastjob)" = failed ] && has "损坏" "$(lastmsg)" "备份文件损坏" || bad "损坏的 tar 要 failed"
  [ "$(cat "$T/ce/com.example.app/files/token")" = keepme ] && ok || bad "损坏时不能动现有数据"
  # 没有备份 / 包名对不上
  out=$(run "$sh" "restore com.example.app $D/nowhere"); has "没备份" "$out" "err 没找到备份"
  sed -i 's/^pkg=.*/pkg=com.other.app/' "$B/backup.meta"; run "$sh" "restore com.example.app $D" >/dev/null
  [ "$(lastjob)" = failed ] && has "meta 对不上" "$(lastmsg)" "对不上" || bad "meta 包名不符要 failed"

  # ---- delete / busy / 后台 ----
  run "$sh" "app com.example.app $D" >/dev/null
  out=$(run "$sh" "delete com.example.app $D" "delete com.example.app $D" "list $D")
  has "delete" "$out" "ok backup delete com.example.app"; has "delete 不存在" "$out" "本来就没有"
  [ ! -e "$B" ] && ok || bad "delete 要删目录"
  sleep 30 & SP=$!
  mkdir -p "$T/state/backup-jobs"; printf 'state=running\nop=backup\npkg=x.y\npid=%s\nt=%s\nmsg=m\n' "$SP" "$(date +%s)" > "$T/state/backup-jobs/9999999999"
  out=$(run "$sh" "app com.example.app $D" "status" "delete com.example.app $D"); has "busy 拒绝" "$out" "err 已有任务在跑"; chk "busy=1" "$out" "busy=1"
  kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
  out=$(run "$sh" "job 9999999999"); chk "进程没了 = failed" "$out" "state=failed"
  out=$(run "$sh" "job abc" "job 12345"); [ "$(printf '%s\n' "$out" | grep -c '^err ')" = 2 ] && ok || bad "job 非法号/不存在"
  # 后台跑(不同步):等它结束
  rm -rf "$T/state/backup-jobs"; SYNC= run "$sh" "app com.example.app $D" >/dev/null
  n=0; while [ $n -lt 50 ]; do [ "$(lastjob 2>/dev/null)" = done ] && break; sleep 0.1; n=$((n + 1)); done
  [ "$(lastjob)" = done ] && [ -f "$B/backup.meta" ] && ok || bad "后台任务应在几秒内完成: $(lastjob)"
}
command -v dash >/dev/null && suite dash
command -v busybox >/dev/null && suite "busybox sh"
echo "通过 $pass 项, 失败 $fail 项"
[ "$fail" = 0 ]
