#!/usr/bin/env bash
# faceunlock 补丁的唯一来源是 tb321fu-faceunlock-patch 仓库的 patch/<底包 ID>/;
# patches/required/tangorpro/<底包 ID>/faceunlock 只是它的同步副本,别直接改。
# 本地编好的 APK、拉下的上游和签名密钥不进仓库,同步时保留(003.settings-entry/files/ 只放本地 APK,整个跳过)。
# 用法: toolkit/sync-faceunlock.sh          从 tb321fu-faceunlock-patch 仓库同步过来
#       toolkit/sync-faceunlock.sh --check  只比较,有差异返回 1(仓库不在就跳过)
# 仓库位置默认 ../tb321fu-faceunlock-patch,可用 FACEUNLOCK_PATCH_DIR 指定。
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${FACEUNLOCK_PATCH_DIR:-$REPO/../tb321fu-faceunlock-patch}/patch
[[ -d $SRC ]] || { echo "sync-faceunlock: 没有 $SRC,跳过"; [[ ${1:-} == --check ]] && exit 0; exit 1; }
KEEP=(--exclude=/parts/002.app/files/FaceUnlock.apk --exclude=/parts/003.settings-entry/files/
      --exclude=/parts/003.settings-entry/src/overlay/res/raw/ --exclude=third_party/ --exclude='*.keystore')
rc=0
for s in "$SRC"/*/; do
    base=$(basename "$s"); dst=$REPO/patches/required/tangorpro/$base/faceunlock
    if [[ ${1:-} == --check ]]; then
        out=$(rsync -anci --delete "${KEEP[@]}" "$s" "$dst/" | grep -v '^\.' || true)
        [[ -z $out ]] || { echo "faceunlock 副本 $base 和 $s 不一致:改动要先改 tb321fu-faceunlock-patch 仓库,再 toolkit/sync-faceunlock.sh"; echo "$out"; rc=1; }
    else
        mkdir -p "$dst" && rsync -a --delete "${KEEP[@]}" "$s" "$dst/"
        echo "已同步 $s → patches/required/tangorpro/$base/faceunlock"
    fi
done
[[ ${1:-} == --check && $rc == 0 ]] && echo "faceunlock 副本和来源一致"
exit $rc
