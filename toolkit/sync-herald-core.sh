#!/usr/bin/env bash
# herald-core 补丁的唯一来源是 herald-core 仓库的 patch/;patches/required/general/herald-core 只是它的同步副本,别直接改。
# 用法: toolkit/sync-herald-core.sh          从 herald-core 仓库同步过来
#       toolkit/sync-herald-core.sh --check  只比较,有差异返回 1(herald-core 仓库不在就跳过)
# 仓库位置默认 ../herald-core,可用 HERALD_CORE_DIR 指定。
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${HERALD_CORE_DIR:-$REPO/../herald-core}/patch
DST=$REPO/patches/required/general/herald-core
[[ -d $SRC ]] || { echo "sync-herald-core: 没有 $SRC,跳过"; [[ ${1:-} == --check ]] && exit 0; exit 1; }
if [[ ${1:-} == --check ]]; then
    diff -r -I "^NAME=" "$SRC" "$DST" >/dev/null && { echo "herald-core 副本和来源一致"; exit 0; }
    echo "herald-core 副本和 $SRC 不一致:改动要先改 herald-core 仓库,再 toolkit/sync-herald-core.sh"; diff -rq -I "^NAME=" "$SRC" "$DST"; exit 1
fi
rm -rf "$DST" && mkdir -p "$DST" && cp -r "$SRC"/. "$DST"/
sed -i "s#^NAME=.*#NAME=${DST#$REPO/patches/}#" "$DST/patch.conf"
echo "已同步 $SRC → patches/required/general/herald-core"
