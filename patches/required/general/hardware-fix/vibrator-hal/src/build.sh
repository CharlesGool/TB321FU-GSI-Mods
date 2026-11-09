#!/usr/bin/env bash
# 用 NDK(r26+)编 tb321fu-vibrator:  NDK=/path/to/ndk ./build.sh [输出文件]
# 默认输出 ../files/tb321fu-vibrator(模块里提交的预编译件)。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${NDK:?设 NDK 为 NDK 根目录}"
API=${API:-34}
OUT=${1:-$here/../files/tb321fu-vibrator}
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
"$TC/aarch64-linux-android${API}-clang++" -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter \
    -fPIE -pie -static-libstdc++ \
    -o "$OUT" "$here/tb321fu_vibrator.cpp" -lbinder_ndk -llog -ldl
"$TC/llvm-strip" "$OUT"
echo "NEEDED:"; "$TC/llvm-readelf" -d "$OUT" | grep NEEDED
sha256sum "$OUT"
