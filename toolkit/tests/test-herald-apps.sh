#!/usr/bin/env bash
# herald-apps 通道(patches/required/general/herald-apps)的离线测试:假的 App 数据目录 + 桩函数,用 mksh(真机的 sh)跑插件。
# 覆盖:合法命令、白名单外、参数越界、符号链接 / FIFO / 属主不对的请求、装在 /data/app、回包位置预置符号链接、附带数据。
# 用法: toolkit/tests/test-herald-apps.sh      (要 sudo:App 文件要属于另一个 uid;要 mksh)
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PLUGIN=$REPO/patches/required/general/herald-apps/files/herald-apps.sh
ALLOW=$REPO/patches/required/general/battery/parts/006.app/files/com.lenovo.tb321fu.battery.allow
command -v mksh >/dev/null || { echo "跳过:没装 mksh"; exit 0; }
sudo -n true 2>/dev/null || { echo "跳过:要免密 sudo"; exit 0; }
PKG=com.lenovo.tb321fu.battery; AU=10123
T=$(mktemp -d "${TMPDIR:-/tmp}/happtest.XXXXXX"); trap 'sudo rm -rf --one-file-system "$T"' EXIT
mkdir -p "$T/apps" "$T/data/$PKG/files" "$T/de/$PKG/files" "$T/w"
{ cat "$ALLOW"; printf 'set\nkeybox_import\n'; } > "$T/apps/$PKG.allow"; touch "$T/packages.list"
sudo chown -R $AU:$AU "$T/data/$PKG" "$T/de/$PKG"
F=$T/data/$PKG/files
cat > "$T/run.sh" <<EOS
PAYDIR=/nonexistent; HERALD_APPS_PKGLIST=$T/packages.list; HERALD_APPS_DIR=$T/apps; HERALD_APPS_DATA=$T/data; HERALD_APPS_W=$T/w
blog() { echo "LOG: \$*" >> $T/log; }
herald_sys() { case "\$*" in *" path "*) echo "package:\${PMPATH:-/system/system_ext/app/TB321FU-Battery/TB321FU-Battery.apk}" ;; *list*) echo "package:$PKG uid:$AU" ;; esac; }
heraldp_cmd_battery() { echo "ok battery \$1"; echo "level=80"; }
HERALDP_ATTACH="set:herald_profile_in:raw keybox_import:herald_keybox_b64_in:b64"
heraldp_cmdf_set() { { echo "ok set"; echo "got=\$(head -1 \$W/herald_profile_in 2>/dev/null)"; } > "\$resp"; }
heraldp_cmdf_keybox_import() { { echo "ok kb"; echo "got=\$(cat \$W/herald_keybox_b64_in 2>/dev/null)"; } > "\$resp"; }
stat() { if [ "\$2" = %C ]; then echo u:object_r:app_data_file:s0:c123,c256,c512,c768; else command stat "\$@"; fi; }
chcon() { :; }
. $PLUGIN
W=\$HAPP_W; mkdir -p \$HAPP_W
heraldapp_once $PKG \${BASE:+$T/de}
EOS
pass=0; fail=0
as_app() { sudo chown -h $AU:$AU "$@"; }
req() { sudo rm -f "$F/herald_resp"; printf '%s\n' "$1" | sudo tee "$F/herald_req.tmp" >/dev/null; as_app "$F/herald_req.tmp"; sudo mv "$F/herald_req.tmp" "$F/herald_req"; }
att() { printf '%s' "$2" | sudo tee "$F/$1" >/dev/null; as_app "$F/$1"; }
run() { sudo env PMPATH="${PMPATH:-}" BASE="${BASE:-}" timeout 20 mksh "$T/run.sh" >/dev/null 2>&1; }
resp() { sudo cat "$F/herald_resp" 2>/dev/null; }
chk() { # chk <说明> <期望:none 或回包第一行> [回包里应有的行]
  local first; first=$(resp | head -1)
  if [ -e "$F/herald_req" ]; then fail=$((fail+1)); echo "  FAIL $1: 请求没被取走"; return; fi
  if [ "$2" = none ]; then
    if sudo test -e "$F/herald_resp"; then fail=$((fail+1)); echo "  FAIL $1: 不该有回包,有 [$first]"; else pass=$((pass+1)); fi; return
  fi
  [ "$first" = "$2" ] || { fail=$((fail+1)); echo "  FAIL $1: 回包 [$first],应为 [$2]"; return; }
  [ "$(sudo stat -c '%u %a' "$F/herald_resp")" = "$AU 600" ] || { fail=$((fail+1)); echo "  FAIL $1: 回包属主/权限 $(sudo stat -c '%u %a' "$F/herald_resp")"; return; }
  if [ -n "${3:-}" ] && ! resp | grep -qxF -- "$3"; then fail=$((fail+1)); echo "  FAIL $1: 回包里没有 [$3]"; return; fi
  pass=$((pass+1))
}
req "battery info"; run; chk 合法命令 "ok battery info" "level=80"
req "battery limit 80 95"; run; chk 带参数 "ok battery limit 80 95"
req "reboot"; run; chk 白名单外 "err not allowed"
req "battery limit 101"; run; chk 参数越界 "err not allowed"
req "battery info; reboot"; run; chk 拼接命令 "err not allowed"
sudo rm -f "$F/herald_resp"; sudo ln -sf /etc/shadow "$F/herald_req"; as_app "$F/herald_req"; run; chk 符号链接请求 none
sudo rm -f "$F/herald_resp"; sudo mkfifo "$F/herald_req"; as_app "$F/herald_req"; run; chk FIFO请求 none
sudo rm -f "$F/herald_resp"; echo "battery info" | sudo tee "$F/herald_req" >/dev/null; run; chk 属主不是App none
req "battery info"; PMPATH=/data/app/~~x/$PKG-1/base.apk run; chk 装在data_app none
req "battery info"; sudo ln -sf /etc/passwd "$F/herald_resp.tmp"; as_app "$F/herald_resp.tmp"; run; chk 回包位置预置链接 "ok battery info"
[ "$(stat -c %u /etc/passwd)" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL /etc/passwd 属主被改"; }
att herald_profile_in '{"fingerprint":"a/b"}'; req "set"; run; chk 附带数据 "ok set" 'got={"fingerprint":"a/b"}'
sudo test -e "$F/herald_profile_in" && { fail=$((fail+1)); echo "  FAIL 附带文件没删"; } || pass=$((pass+1))
att herald_keybox_b64_in "$(printf 'QUJD\nREVG\r\n')"; req "keybox_import"; run; chk b64去换行 "ok kb" "got=QUJDREVG"
sudo ln -sf /etc/hostname "$F/herald_profile_in"; as_app "$F/herald_profile_in"; req "set"; run; chk 附带是链接 "ok set" "got="
printf '{"fingerprint":"x"}' | sudo tee "$F/herald_profile_in" >/dev/null; req "set"; run; chk 附带属主不对 "ok set" "got="
# DE(解锁前):同一套规则,在 /data/user_de/0/<包>/files 里收发
F=$T/de/$PKG/files
req "battery info"; BASE=de run; chk DE目录 "ok battery info" "level=80"
req "reboot"; BASE=de run; chk DE白名单外 "err not allowed"
echo "通过 $pass 项, 失败 $fail 项"
[ $fail = 0 ]
