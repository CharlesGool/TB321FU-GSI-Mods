#!/usr/bin/env bash
# 9008 保数据刷机 patch 包的总入口:原厂 9008 包 + 新 system + vbmeta_system + boot 集 → 刷机目录标准的 7z。
#
# 用法:
#   make_9008_patch.sh [--conf device.conf] [选项…]
#
# 选项(给了 --conf 时,没写的从 conf 里的 FLASH9008_* / VERSION / DEVICE 取):
#   --stock-dir DIR        原厂 9008 包 image/ 解出的目录,可写多次,按顺序找文件      FLASH9008_STOCK_DIRS
#   --base-xml FILE        已验证保数据的 LUN0 rawprogram XML(基准)                  FLASH9008_BASE_XML
#   --system FILE          新 system 镜像(带 AVB hashtree footer)
#   --vbmeta-system FILE   和它配套的 vbmeta_system.img
#   --system-out DIR       toolkit/build.sh 输出目录下的 system/(代替上面两项,取 $IMAGE_NAME.img 和 vbmeta_system.img)
#   --boot-set DIR         boot/init_boot/vendor_boot/vbmeta.img 所在目录(toolkit/build.sh 输出目录下的 firmware/)
#   --version N            新版本号(数字)。conf 里 VERSION=V67 时自动取 67
#   --base-version B       增量基准的版本号                                             FLASH9008_BASE_VERSION
#   --base-image FILE      基准版本的 system 镜像(= 用户那边的 super_4_vB.img)       FLASH9008_BASE_IMAGE
#   --base-sha256 HEX      基准镜像应有的 sha256                                       FLASH9008_BASE_SHA256
#   --xdelta-exe FILE      Windows 版 xdelta3.exe                                     FLASH9008_XDELTA_EXE
#   --xdelta-window BYTES  xdelta3 源窗口(-B),默认 536870912(512MiB)               FLASH9008_XDELTA_WINDOW
#                          比默认的 64MiB 大很多:新旧镜像之间删/插了超过 64MiB 内容时,后面数据整体平移,
#                          窗口太小就匹配不上,补丁会膨胀到接近整个镜像
#   --device NAME          7z 文件名前缀                                               DEVICE
#   --include-boot-set     boot 集也打进包                                             FLASH9008_INCLUDE_BOOT_SET=1
#   --note TEXT            版本备注(必填)
#   --out DIR              输出目录(必填)
#
# 流程(任何一步失败就停):
#   1. super_1:原厂 super_1.img 的 lp 元数据里 system_a 改成 system 镜像大小(lp.py)
#   2. LUN0 XML:以基准为底只改 super_1 / system_a 两行,全文 diff + 受保护分区检查(mk_rawprogram.py)
#   3. super 布局:按新 XML 虚拟拼 super,检查每个分片落在哪个逻辑分区、有没有重叠越界(simsuper.py --check)
#   4. AVB:从 vbmeta 往下核对整条链(check_avb.py)
#   5. 打包:xdelta 补丁 + 还原自检 + manifest + 7z(mk_patch_pkg.py)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
die() { echo "[9008] 错误: $*" >&2; exit 1; }

CONF= ; STOCK_DIRS=(); BASE_XML= ; SYSTEM= ; VBS= ; SYSOUT= ; BOOTSET= ; N= ; B= ; BASE_IMG= ; BASE_SHA= ; XD= ; XDW= ; DEV= ; INCL= ; NOTE= ; OUT=
while [[ $# -gt 0 ]]; do
    case $1 in
        --conf) CONF=$(realpath "$2"); shift 2 ;;
        --stock-dir) STOCK_DIRS+=("$2"); shift 2 ;;
        --base-xml) BASE_XML=$2; shift 2 ;;
        --system) SYSTEM=$2; shift 2 ;;
        --vbmeta-system) VBS=$2; shift 2 ;;
        --system-out) SYSOUT=$2; shift 2 ;;
        --boot-set) BOOTSET=$2; shift 2 ;;
        --version) N=$2; shift 2 ;;
        --base-version) B=$2; shift 2 ;;
        --base-image) BASE_IMG=$2; shift 2 ;;
        --base-sha256) BASE_SHA=$2; shift 2 ;;
        --xdelta-exe) XD=$2; shift 2 ;;
        --xdelta-window) XDW=$2; shift 2 ;;
        --device) DEV=$2; shift 2 ;;
        --include-boot-set) INCL=1; shift ;;
        --note) NOTE=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) die "不认识的参数 $1" ;;
    esac
done

if [[ -n $CONF ]]; then
    REPO=$(dirname "$(dirname "$HERE")")
    # shellcheck disable=SC1090
    source "$CONF"
    # conf 里的 FLASH9008_STOCK_DIRS 是候选位置,不存在的跳过(命令行 --stock-dir 给的必须存在)
    if [[ ${#STOCK_DIRS[@]} -eq 0 ]]; then
        for d in "${FLASH9008_STOCK_DIRS[@]}"; do [[ -d $d ]] && STOCK_DIRS+=("$d"); done
        [[ ${#STOCK_DIRS[@]} -gt 0 ]] || die "找不到原厂 9008 解出的 image 目录,试过: ${FLASH9008_STOCK_DIRS[*]}(重启后 /tmp 会清空,要重新解压;或用 --stock-dir 指定)"
    fi
    BASE_XML=${BASE_XML:-${FLASH9008_BASE_XML:-}}
    B=${B:-${FLASH9008_BASE_VERSION:-}}
    BASE_IMG=${BASE_IMG:-${FLASH9008_BASE_IMAGE:-}}
    BASE_SHA=${BASE_SHA:-${FLASH9008_BASE_SHA256:-}}
    XD=${XD:-${FLASH9008_XDELTA_EXE:-}}
    XDW=${XDW:-${FLASH9008_XDELTA_WINDOW:-}}
    DEV=${DEV:-${DEVICE:-}}
    [[ -n $INCL ]] || { [[ ${FLASH9008_INCLUDE_BOOT_SET:-0} == 1 ]] && INCL=1; }
    if [[ -z $N && -n ${VERSION:-} ]]; then
        [[ $VERSION =~ ^V([0-9]+)$ ]] || die "VERSION=$VERSION 不是 V<数字>"
        N=${BASH_REMATCH[1]}
    fi
    if [[ -n $SYSOUT ]]; then
        if [[ -f $SYSOUT/IMAGE_NAME ]]; then _img=$(cat "$SYSOUT/IMAGE_NAME"); else _img=${IMAGE_NAME:-system_$VERSION}; fi
        SYSTEM=${SYSTEM:-$SYSOUT/$_img.img}
        VBS=${VBS:-$SYSOUT/vbmeta_system.img}
    fi
fi
[[ -n $SYSOUT && -z $SYSTEM ]] && die "--system-out 要和 --conf 一起用(要从 conf 拿 IMAGE_NAME),不然直接给 --system"
for v in BASE_XML SYSTEM VBS BOOTSET N B BASE_IMG XD DEV NOTE OUT; do [[ -n ${!v} ]] || die "缺参数: $v(见 --help)"; done
[[ ${#STOCK_DIRS[@]} -gt 0 ]] || die "缺 --stock-dir"
[[ $N =~ ^[0-9]+$ && $B =~ ^[0-9]+$ ]] || die "版本号要是数字: N=$N B=$B"
for f in "$BASE_XML" "$SYSTEM" "$VBS" "$BASE_IMG" "$XD"; do [[ -f $f ]] || die "文件不存在: $f"; done
for d in "${STOCK_DIRS[@]}"; do [[ -d $d ]] || die "目录不存在: $d"; done

# 补丁选择要一致:system 和 boot 集是同一次构建出来的(toolkit/build.sh 往两边各拷一份同样的 SELECTION.txt)
if [[ -n $SYSOUT && -f $SYSOUT/SELECTION.txt && -f $BOOTSET/SELECTION.txt ]]; then
    cmp -s "$SYSOUT/SELECTION.txt" "$BOOTSET/SELECTION.txt" || die "system 和 boot 集不是同一次构建(SELECTION.txt 不一样):
  $SYSOUT/SELECTION.txt
  $BOOTSET/SELECTION.txt
  用 toolkit/build.sh 重新构建一次再打包"
    echo "[9008] 补丁选择一致: $(grep '^rules: ' "$SYSOUT/SELECTION.txt" | sed 's/^rules: //')"
fi

find_stock() {  # find_stock <文件名>  在原厂目录里按顺序找
    local d; for d in "${STOCK_DIRS[@]}"; do [[ -e $d/$1 ]] && { echo "$d/$1"; return 0; }; done; return 1
}
OUT=$(realpath -m "$OUT"); W=$OUT/work_v$N
rm -rf "$W"; mkdir -p "$W/image"
SYS_SIZE=$(stat -L -c %s "$SYSTEM")
(( SYS_SIZE % 4096 == 0 )) || die "system 镜像 $SYS_SIZE 字节,不是 4096 的倍数"
S1_NAME=super_1_v$N.img; S4_NAME=super_4_v$N.img; XML_NAME=rawprogram_save_persist_unsparse0_v$N.xml

echo "==== 1. super_1(lp 元数据里 system_a = $SYS_SIZE 字节)"
STOCK_S1=$(find_stock super_1.img) || die "原厂目录里没有 super_1.img"
python3 -I "$HERE/lp.py" resize "$STOCK_S1" system_a "$SYS_SIZE" "$W/image/$S1_NAME" | grep -E 'checksums|system_a ' | sort -u

echo; echo "==== 2. LUN0 rawprogram XML(基准 $(basename "$BASE_XML"))"
others=()
for i in 1 2 3 4 5; do f=$(find_stock rawprogram$i.xml) && others+=("$f"); done
[[ ${#others[@]} -gt 0 ]] || echo "  注意: 原厂目录里没找到 rawprogram1..5.xml,只检查 LUN0"
python3 -I "$HERE/mk_rawprogram.py" --base "$BASE_XML" --super1 "$W/image/$S1_NAME" --system "$SYSTEM" \
    --super1-name "$S1_NAME" --system-name "$S4_NAME" --out "$W/image/$XML_NAME" --check-xml "${others[@]}"

echo; echo "==== 3. super 布局(按新 XML 虚拟拼 super)"
ln -sf "$(realpath "$SYSTEM")" "$W/image/$S4_NAME"
python3 -I "$HERE/simsuper.py" "$W/image/$XML_NAME" "$W/unused" "$W/image" "${STOCK_DIRS[@]}" --check

echo; echo "==== 4. AVB 链"
dirs=(--dir "$W/image"); for d in "${STOCK_DIRS[@]}"; do dirs+=(--dir "$d"); done
python3 -I "$HERE/check_avb.py" --xml "$W/image/$XML_NAME" "${dirs[@]}" \
    --part boot="$BOOTSET/boot.img" --part init_boot="$BOOTSET/init_boot.img" --part vendor_boot="$BOOTSET/vendor_boot.img" \
    --vbmeta "$BOOTSET/vbmeta.img" --vbmeta-system "$VBS"

echo; echo "==== 5. 打包"
pk=(--version "$N" --note "$NOTE" --device "$DEV" --system "$SYSTEM" --vbmeta-system "$VBS"
    --super1 "$W/image/$S1_NAME" --rawprogram "$W/image/$XML_NAME" --base-version "$B" --base-image "$BASE_IMG"
    --boot-set "$BOOTSET" --xdelta-exe "$XD" --out "$OUT")
[[ -n ${XDW:-} ]] && pk+=(--xdelta-window "$XDW")
[[ -n $BASE_SHA ]] && pk+=(--base-sha256 "$BASE_SHA")
[[ -n $INCL ]] && pk+=(--include-boot-set)
python3 -I "$HERE/mk_patch_pkg.py" "${pk[@]}"
rm -f "$W/image/$S4_NAME"
for f in "${SYSOUT:+$SYSOUT/SELECTION.txt}" "$BOOTSET/SELECTION.txt"; do
    [[ -n $f && -f $f ]] && cp -f "$f" "$OUT/SELECTION-v$N-$(basename "$(dirname "$f")").txt"
done
echo; echo "[9008] 完成。super_1 / XML 在 $W/image/,包在 $OUT/"
