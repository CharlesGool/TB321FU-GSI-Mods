#!/usr/bin/env bash
# 拉 PixelOS ParanoidSense 上游(固定 commit),里面有旷视(Megvii)的 so、vendorImplPrebuilt.jar 和模型文件,
# 重新构建 FaceUnlock.apk 时要用。平时不用跑——镜像里放的是 files/ 下已经构建好的 APK。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=https://github.com/PixelOS-AOSP/packages_apps_ParanoidSense.git
COMMIT=a500478bbb0e2933276d57796d9b410f0f8e90f8
DST=$HERE/third_party/ParanoidSense

if [[ ! -d $DST/.git ]]; then
    git clone --filter=blob:none --no-checkout "$REPO" "$DST"
fi
git -C "$DST" fetch --depth 1 origin "$COMMIT"
git -C "$DST" -c advice.detachedHead=false checkout "$COMMIT"
ls -l "$DST/lib" "$DST/res/raw"
