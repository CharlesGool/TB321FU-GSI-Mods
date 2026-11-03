#!/usr/bin/env bash
# 整个后端 herald-start.sh(连同镜像里所有插件)在 mksh(真机的 sh)下的开机回归测试。不碰真机。
#   用法: [HERALD_START_OVERRIDE=<herald-start.sh>] toolkit/test-herald-start-full.sh <system 镜像.img | --repo>
#   --repo:不用镜像,直接从仓库里取 herald-core 的 herald-start.sh 和几个有代表性的插件(引擎、Wi-Fi、按应用伪装、导航栏),不需要 sudo
# 从镜像取 /system/etc/herald_payload 下的 herald-start.sh、plugins/、app-spoof/,路径换到临时目录,
# 系统命令打桩(getprop/resetprop/keymint/inject 等),按 app / global / off 三种伪装状态各跑 10 秒:
#   - 10 秒内不能自己退出(V84:主脚本变量未定义退出;V85:EXIT trap 让插件里的报错变成整个退出)
#   - shell 不能报任何错(stderr 里只允许启动那一行)
# 需要 mksh(apt install mksh)和 sudo(挂载 erofs)。
set -u
IMG=${1:?用法: $0 <system 镜像.img | --repo>}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SEEDDIR=${TB321FU_DATA:-$REPO/../tb321fu_pixelos_15_tangorpro_ap3a.241005.015}/legacy/gsi/strong/herald-payload/seed
command -v mksh >/dev/null || { echo "缺 mksh(apt install mksh)"; exit 2; }
T=$(mktemp -d); M=$T/mnt; mkdir -p "$M"
trap 'mountpoint -q "$M" && sudo umount "$M"; rm -rf "$T"' EXIT
if [ "$IMG" = --repo ]; then
  P=$T/repo-payload; mkdir -p "$P/plugins" "$P/app-spoof"
  cp "$REPO/patches/required/general/herald-core/files/herald-start.sh" "$P/"
  cp "$REPO/patches/required/general/attestation-fix/files/00-attestation.sh" "$REPO/patches/optional/hotspot-control/parts/002.control/files/wifi.sh" \
     "$REPO/patches/optional/spoof/app-spoof/files/app-spoof.sh" "$REPO/patches/optional/navbar-hide/parts/004.control/files/navbar.sh" "$P/plugins/"
  touch "$P/app-spoof/targets.default"
else
  sudo mount -o loop,ro -t erofs "$IMG" "$M" || { echo "挂不上 $IMG"; exit 2; }
  P=$M/system/etc/herald_payload
fi
# HERALD_START_OVERRIDE=<文件>:用仓库里改过的脚本替换镜像里的(出包前先测)
mkdir -p "$T/src"; cp "${HERALD_START_OVERRIDE:-$P/herald-start.sh}" "$T/src/herald-start.sh"; cp -r "$P/plugins" "$T/src/"; [ -d "$P/app-spoof" ] && cp -r "$P/app-spoof" "$T/src/"
[ "$IMG" = --repo ] || sudo umount "$M"
pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "  FAIL: $*"; }
for mode in app global off; do
  X=$T/$mode; mkdir -p "$X"/{pay/bin,pay/seed,cfg/data,state,bin,meta}
  cp -r "$T/src/plugins" "$X/pay/"; [ -d "$T/src/app-spoof" ] && cp -r "$T/src/app-spoof" "$X/pay/"
  cp "$SEEDDIR"/* "$X/pay/seed/"; cp "$SEEDDIR/pif_fingerprint.json" "$X/cfg/data/"
  [ "$mode" != off ] && touch "$X/cfg/data/global_pif_enabled"
  [ "$mode" = global ] && echo global > "$X/cfg/data/spoof_mode"
  for b in keymint inject; do printf '#!/bin/sh\nsleep 100\n' > "$X/pay/bin/$b"; done
  printf '#!/bin/sh\nexit 0\n' > "$X/pay/bin/resetprop"
  for c in getprop setprop log chcon restorecon pm am cmd dumpsys settings pidof; do printf '#!/bin/sh\necho real\n' > "$X/bin/$c"; done
  chmod +x "$X/pay/bin/"* "$X/bin/"*
  sed -e "s#/system/etc/herald_payload#$X/pay#g" -e "s#/data/misc/keystore/herald#$X/cfg#g" -e "s#/data/adb/herald#$X/state#g" \
      -e "s#/data/local/tmp/herald#$X/shdir#g" -e "s#/metadata/herald_log#$X/meta#g" -e "s#/system/bin/log#$X/bin/log#g" -e '/^chown/d' \
      "$T/src/herald-start.sh" > "$X/start.sh"
  # 插件也要换路径(引擎插件里有 CFG=/data/misc/keystore/herald 等)
  for _p in "$X"/pay/plugins/*.sh; do
    sed -e "s#/system/etc/herald_payload#$X/pay#g" -e "s#/data/misc/keystore/herald#$X/cfg#g" -e "s#/data/adb/herald#$X/state#g" \
        -e "s#/data/local/tmp/herald#$X/shdir#g" -e "s#/metadata/herald_log#$X/meta#g" -e '/^chown/d' "$_p" > "$_p.new" && mv "$_p.new" "$_p"
  done
  ( cd "$X" && PATH=$X/bin:$PATH timeout 10 mksh "$X/start.sh" > "$X/out.txt" 2>"$X/stderr.txt" ); rc=$?
  [ "$rc" = 124 ] && ok || { bad "$mode: 后端 10 秒内自己退出了 rc=$rc"; tail -3 "$X/out.txt" | sed 's/^/      | /'; }
  errs=$(cat "$X/stderr.txt" "$X/meta/herald-start.err" 2>/dev/null | grep -v "herald-start 启动 pid" | grep -v '^$' | grep -v '^real$' | grep -v 'injector.log: open: No such file' | grep -v '^Terminated')   # injector.log 由注入 keystore2 的模块写(沙盒没有);Terminated 是 10 秒到时杀进程
  [ -z "$errs" ] && ok || { bad "$mode: shell 报错"; echo "$errs" | head -5 | sed 's/^/      | /'; }
done
echo "通过 $pass,失败 $fail"; [ "$fail" = 0 ]
