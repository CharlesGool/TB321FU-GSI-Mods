#!/usr/bin/env bash
# tango 补丁的唯一来源是 tb321fu-tango-patch 仓库的 patch/;patches/required/general/tango 只是它的同步副本,别直接改。
# 用法: toolkit/sync-tango.sh          从 tb321fu-tango-patch 仓库同步过来
#       toolkit/sync-tango.sh --check  只比较,有差异返回 1(tb321fu-tango-patch 仓库不在就跳过)
# 仓库位置默认 ../tb321fu-tango-patch,可用 TANGO_PATCH_DIR 指定。
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${TANGO_PATCH_DIR:-$REPO/../tb321fu-tango-patch}/patch
DST=$REPO/patches/required/general/tango
[[ -d $SRC ]] || { echo "sync-tango: 没有 $SRC,跳过"; [[ ${1:-} == --check ]] && exit 0; exit 1; }
if [[ ${1:-} == --check ]]; then
    diff -r -I "^NAME=" "$SRC" "$DST" >/dev/null && { echo "tango 副本和来源一致"; exit 0; }
    echo "tango 副本和 $SRC 不一致:改动要先改 tb321fu-tango-patch 仓库,再 toolkit/sync-tango.sh"; diff -rq -I "^NAME=" "$SRC" "$DST"; exit 1
fi
rm -rf "$DST" && mkdir -p "$DST" && cp -r "$SRC"/. "$DST"/
sed -i "s#^NAME=.*#NAME=${DST#$REPO/patches/}#" "$DST/patch.conf"
echo "已同步 $SRC → patches/required/general/tango"
