#!/usr/bin/env bash
# 出完整的 9008 刷机包(不是增量补丁):原厂 9008 包整套 + 新 system + vbmeta_system + boot 集 → 一个可以直接刷的目录(可选 7z)。
# 给公开发布用:用户有这个目录就能刷,不需要手里有任何旧版本。
#
# 用法:
#   make_9008_full.sh --conf device.conf --system-out DIR --boot-set DIR --stock-root DIR --label 名字 --note 文字 --out DIR [--7z]
#     --stock-root   原厂 9008 包解压出来的根目录(有 flash.bat、tool/、image/)
#     --label        包目录名,一般用 system/IMAGE_NAME
#     --7z           再打成 <label>.7z
#
# 包里改了这些(其余文件和原厂包是同一份,用硬链接,不占额外空间):
#   image/super_1.img、image/super_4.img   新的 lp 元数据和 system 分片
#   image/boot.img init_boot.img vendor_boot.img vbmeta.img vbmeta_system.img
#   image/rawprogram_save_persist_unsparse0.xml   清数据版(原厂语义,flash.bat 用它),只换 super_1 / system_a 两行
#   image/rawprogram_keep_data_unsparse0.xml     保数据版(userdata/metadata/persist 不动),flash_keep_data.bat 用它
#   刷机说明.txt、MODULES.txt、SELECTION.txt
# 流程和 make_9008_patch.sh 前四步一样(super_1、XML、super 布局、AVB 链),任何一步失败就停。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export REPO=${REPO:-$(dirname "$(dirname "$HERE")")}   # device.conf 要用
die() { echo "[9008] 错误: $*" >&2; exit 1; }
CONF= SYSOUT= BOOTSET= ROOT= LABEL= NOTE= OUT= DO7Z=0
while (( $# )); do
    case $1 in
        --conf) CONF=$2; shift 2 ;; --system-out) SYSOUT=$2; shift 2 ;; --boot-set) BOOTSET=$2; shift 2 ;;
        --stock-root) ROOT=$2; shift 2 ;; --label) LABEL=$2; shift 2 ;; --note) NOTE=$2; shift 2 ;; --out) OUT=$2; shift 2 ;;
        --7z) DO7Z=1; shift ;; -h|--help) sed -n '2,19p' "$0"; exit 0 ;; *) die "不认识的参数 $1" ;;
    esac
done
for v in CONF SYSOUT BOOTSET ROOT NOTE OUT; do [[ -n ${!v} ]] || die "缺参数: $v"; done
# shellcheck disable=SC1090
source "$CONF"
[[ -f $SYSOUT/IMAGE_NAME ]] && IMG=$(cat "$SYSOUT/IMAGE_NAME") || IMG=${IMAGE_NAME:-system_$VERSION}
LABEL=${LABEL:-$IMG}
SYSTEM=$SYSOUT/$IMG.img; VBS=$SYSOUT/vbmeta_system.img; BASE_XML=${FLASH9008_BASE_XML:?}
STOCK_IMG=$ROOT/image
for f in "$SYSTEM" "$VBS" "$BASE_XML" "$ROOT/flash.bat" "$STOCK_IMG/super_1.img" "$STOCK_IMG/rawprogram_save_persist_unsparse0.xml" "$BOOTSET/boot.img" "$BOOTSET/vbmeta.img"; do
    [[ -f $f ]] || die "文件不存在: $f"
done
if [[ -f $SYSOUT/SELECTION.txt && -f $BOOTSET/SELECTION.txt ]]; then
    cmp -s "$SYSOUT/SELECTION.txt" "$BOOTSET/SELECTION.txt" || die "system 和 boot 集不是同一次构建(SELECTION.txt 不一样),重新构建一次再打包"
fi
OUT=$(realpath -m "$OUT"); W=$OUT/work; PKG=$OUT/$LABEL
rm -rf "$W" "$PKG"; mkdir -p "$W/image"
SYS_SIZE=$(stat -L -c %s "$SYSTEM")
(( SYS_SIZE % 4096 == 0 )) || die "system 镜像 $SYS_SIZE 字节,不是 4096 的倍数"

echo "==== 1. super_1(lp 元数据里 system_a = $SYS_SIZE 字节)"
python3 -I "$HERE/lp.py" resize "$STOCK_IMG/super_1.img" system_a "$SYS_SIZE" "$W/super_1.img" | grep -E 'checksums|system_a ' | sort -u

echo; echo "==== 2. LUN0 rawprogram XML"
others=(); for i in 1 2 3 4 5; do [[ -f $STOCK_IMG/rawprogram$i.xml ]] && others+=("$STOCK_IMG/rawprogram$i.xml"); done
echo "-- 保数据版(基准 $(basename "$BASE_XML"))"
python3 -I "$HERE/mk_rawprogram.py" --base "$BASE_XML" --super1 "$W/super_1.img" --system "$SYSTEM" \
    --super1-name super_1.img --system-name super_4.img --out "$W/rawprogram_keep_data_unsparse0.xml" --check-xml "${others[@]}"
echo "-- 清数据版(基准 原厂 rawprogram_save_persist_unsparse0.xml)"
python3 -I "$HERE/mk_rawprogram.py" --allow-wipe --base "$STOCK_IMG/rawprogram_save_persist_unsparse0.xml" --super1 "$W/super_1.img" --system "$SYSTEM" \
    --super1-name super_1.img --system-name super_4.img --out "$W/rawprogram_save_persist_unsparse0.xml"

echo; echo "==== 3. super 布局(按新 XML 虚拟拼 super)"
mkdir -p "$W/layout"; ln -sf "$(realpath "$SYSTEM")" "$W/layout/super_4.img"; ln -sf "$W/super_1.img" "$W/layout/super_1.img"
python3 -I "$HERE/simsuper.py" "$W/rawprogram_keep_data_unsparse0.xml" "$W/unused" "$W/layout" "$STOCK_IMG" --check

echo; echo "==== 4. AVB 链"
python3 -I "$HERE/check_avb.py" --xml "$W/rawprogram_keep_data_unsparse0.xml" --dir "$W/layout" --dir "$STOCK_IMG" \
    --part boot="$BOOTSET/boot.img" --part init_boot="$BOOTSET/init_boot.img" --part vendor_boot="$BOOTSET/vendor_boot.img" \
    --vbmeta "$BOOTSET/vbmeta.img" --vbmeta-system "$VBS"

echo; echo "==== 5. 组装完整包 → $PKG"
cp -al "$ROOT" "$PKG" 2>/dev/null || cp -a "$ROOT" "$PKG"     # 硬链接(同一磁盘),不行就整份拷
rm -rf "$PKG/carved"                                          # 切出来的逻辑分区不是刷机包的一部分
put() { cp --remove-destination "$1" "$PKG/image/$2"; }       # 先删再拷:不动原厂包那份(硬链接是同一个 inode)
put "$W/super_1.img" super_1.img
put "$SYSTEM" super_4.img
for f in boot.img init_boot.img vendor_boot.img vbmeta.img; do put "$BOOTSET/$f" "$f"; done
put "$VBS" vbmeta_system.img
put "$W/rawprogram_keep_data_unsparse0.xml" rawprogram_keep_data_unsparse0.xml
put "$W/rawprogram_save_persist_unsparse0.xml" rawprogram_save_persist_unsparse0.xml
sed 's/rawprogram_save_persist_unsparse0\.xml/rawprogram_keep_data_unsparse0.xml/' "$PKG/flash.bat" > "$PKG/flash_keep_data.bat.tmp"
# flash.bat 是 UTF-8 + CRLF;保持原样
mv "$PKG/flash_keep_data.bat.tmp" "$PKG/flash_keep_data.bat"
for m in "$SYSOUT/MODULES.txt" "$(dirname "$SYSOUT")/MODULES.txt"; do [[ -f $m ]] && { cp "$m" "$PKG/MODULES.txt"; break; }; done
[[ -f $SYSOUT/SELECTION.txt ]] && cp "$SYSOUT/SELECTION.txt" "$PKG/SELECTION.txt"
SYS_SHA=$(sha256sum "$SYSTEM" | cut -d' ' -f1)
cat > "$PKG/刷机说明.txt" <<T
$LABEL
$NOTE

底包: 联想拯救者 Y700 三代(TB321FU)ZUI 17.0.12 原厂 9008 包(固件、vendor、boot 等),system 换成 Pixel Tablet GSI(Mystic)+ 补丁。
system 镜像 sha256: $SYS_SHA

怎么刷(Windows,平板进 9008 模式,装好高通 9008 驱动):
  1. 清数据刷机(干净安装,推荐从别的系统换过来时用):双击 flash.bat
  2. 保数据刷机(从本项目上一版升级,不清用户数据):双击 flash_keep_data.bat
  都是输入 9008 端口号(比如 COM18)后自动刷。刷完没自动开机,长按电源键 + 音量下 8 秒以上重启。
  保数据刷机只适用于原来就刷着本项目的系统;从原厂系统或别的 ROM 直接保数据刷,开机大概率起不来,请用清数据版。

补丁列表见 MODULES.txt,这次选的是什么见 SELECTION.txt。
T
rm -rf "$W"                                                   # 中间文件不留
echo "  包目录: $PKG ($(du -sh --apparent-size "$PKG" | cut -f1))"
if (( DO7Z )); then
    echo; echo "==== 6. 打 7z"
    ( cd "$OUT" && rm -f "$LABEL.7z" && 7z a -t7z -mx=5 -mmt=on "$LABEL.7z" "$LABEL" >/dev/null && sha256sum "$LABEL.7z" | tee "$LABEL.7z.sha256" )
fi
echo; echo "[9008] 完成: $PKG"
