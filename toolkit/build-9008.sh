#!/usr/bin/env bash
# 一条命令出 9008 保数据刷机包:原始材料 → 依次 apply 选中的补丁 → 打包。三步用同一份补丁选择。
#
# 用法: toolkit/build-9008.sh <device.conf> <输出目录> --note "备注" [--profile 预设] [--with 规则] [--without 规则]
#                             [--reuse] [交给 make_9008_patch.sh 的其他参数,如 --include-boot-set]
#
#   1. 构建:toolkit/build.sh → <输出目录>/system、<输出目录>/firmware
#            GSI 底包 + 原厂固件放进同一个工作区,依次打补丁,出 system 镜像 + vbmeta_system 和 boot 集(boot/init_boot/vendor_boot/vbmeta)
#   2. 打包:toolkit/flash9008/make_9008_patch.sh → <输出目录>/9008   原厂 9008 包 + 上一步 → 刷机目录标准的 7z
#
#   --full    出完整刷机包(原厂 9008 整套 + 新 system 等,可以直接刷),不出增量补丁;--7z 再打成 7z。输出在 <输出目录>/package/
#   --reuse   不重新构建,用输出目录里已有的(打包时会核对 system 和 boot 集是同一次构建出来的)
#   选补丁的规则见 toolkit/lib/select.sh;PROFILE/WITH/WITHOUT 环境变量也认。
set -euo pipefail
[[ $# -ge 2 ]] || { sed -n '2,14p' "$0"; exit 1; }
CONF=$(realpath "$1"); OUT=$(realpath -m "$2"); shift 2
TOOLKIT=$(cd "$(dirname "$0")" && pwd)
export REPO=${REPO:-$(dirname "$TOOLKIT")}   # device.conf 要用
REUSE=0 NOTE= PASS=() FULL=0 DO7Z=0
while (( $# )); do
    case $1 in
        --profile) export PROFILE=$2; shift 2 ;;
        --with)    export WITH=${WITH:+$WITH,}$2; shift 2 ;;
        --without) export WITHOUT=${WITHOUT:+$WITHOUT,}$2; shift 2 ;;
        --reuse) REUSE=1; shift ;;
        --full) FULL=1; shift ;;
        --7z) DO7Z=1; shift ;;
        --note) NOTE=$2; shift 2 ;;
        *) PASS+=("$1"); shift ;;
    esac
done
# 工作区要放在本机的 Linux 文件系统上(ext4 等):构建用 sudo cp -a 保留属主、权限、SELinux 标签,NAS(cifs/nfs)和 fuse 不支持
case $(stat -f -c %T "$(dirname "$OUT")" 2>/dev/null) in
    cifs|smb*|nfs*|fuseblk|fuse*|9p|v9fs)
        echo "输出目录 $OUT 在不支持属主/权限/标签的文件系统上($(stat -f -c %T "$(dirname "$OUT")")),换到本机磁盘,例如 /tmp/9008-out" >&2; exit 1 ;;
esac
[[ -n $NOTE ]] || { echo "缺 --note \"版本备注\"(写进包里的补丁说明)"; exit 1; }
export PROFILE=${PROFILE:-} WITH=${WITH:-} WITHOUT=${WITHOUT:-}

if (( REUSE )); then echo "==== 1/2 构建:复用 $OUT"
else echo "==== 1/2 构建"; "$TOOLKIT/build.sh" "$CONF" "$OUT"; fi
if (( FULL )); then
    echo "==== 2/2 出完整 9008 刷机包"
    ROOT=$(source "$CONF" >/dev/null 2>&1; for d in "${FLASH9008_STOCK_DIRS[@]}"; do [[ -f $(dirname "$d")/flash.bat ]] && { dirname "$d"; break; }; done) || true
    [[ -n $ROOT ]] || { echo "找不到原厂 9008 包的根目录(要有 flash.bat 和 image/),见 FLASH9008_STOCK_DIRS" >&2; exit 1; }
    exec "$TOOLKIT/flash9008/make_9008_full.sh" --conf "$CONF" --system-out "$OUT/system" --boot-set "$OUT/firmware" \
        --stock-root "$ROOT" --note "$NOTE" --out "$OUT/package" $( (( DO7Z )) && echo --7z )
fi
echo "==== 2/2 打 9008 包"
"$TOOLKIT/flash9008/make_9008_patch.sh" --conf "$CONF" --system-out "$OUT/system" --boot-set "$OUT/firmware" \
    --note "$NOTE" --out "$OUT/9008" "${PASS[@]}"
