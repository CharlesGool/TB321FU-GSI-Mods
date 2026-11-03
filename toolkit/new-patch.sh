#!/usr/bin/env bash
# 用法: toolkit/new-patch.sh <分类/补丁名> [--parts]   分类 = required/general(通用修复)| required/<底包前缀>(特定底包限定,如 required/tangorpro)| optional(可选)| debug(调试)
#   从 docs/patch-template/ 建一个新补丁骨架(默认不带 parts/)
# 之后:改 patch.conf 和 apply.sh → 加进 devices/<设备>/device.conf 的 MODS → toolkit/gen-index.sh
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:?用法: toolkit/new-patch.sh <required/general|required/<底包前缀>|optional|debug>/<补丁名> [--parts]}
case $NAME in required/*/*|optional/*|debug/*) ;; *) echo "补丁名要以 required/<general 或底包前缀>/、optional/ 或 debug/ 开头"; exit 1 ;; esac
DST=$REPO/patches/$NAME
[[ ! -e $DST ]] || { echo "已存在: $DST"; exit 1; }
mkdir -p "$DST"
sed "s#__NAME__#$NAME#" "$REPO/docs/patch-template/patch.conf" | grep -v '^#' | grep -v '^$' > "$DST/patch.conf"
cp "$REPO/docs/patch-template/apply.sh" "$REPO/docs/patch-template/README.md" "$DST/"
if [[ ${2:-} == --parts ]]; then cp -r "$REPO/docs/patch-template/parts" "$DST/parts"; else sed -i '/^run_parts/d;/^# 合并补丁/d' "$DST/apply.sh"; mkdir -p "$DST/files"; fi
echo "建好 $DST;patch.conf 不带注释,字段说明见 docs/patch-template/patch.conf"
