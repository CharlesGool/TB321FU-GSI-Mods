#!/usr/bin/env bash
# 构建:原始材料 → 依次 apply 选中的补丁 → 打包。
#   1. 准备工作区:GSI 底包解成 system 树($OUT/tree),原厂固件(boot 等)放进 $OUT/firmware
#   2. 按 device.conf 的 MODS 顺序跑选中的补丁。改 system 的改树,改 boot 的往 $OUT/firmware 出东西,两边都改的(selinux/fix)一起改
#   3. 打包:system 树 → erofs → AVB hashtree 签名 + vbmeta_system;boot 集 → 主 vbmeta 重签(toolkit/avb_resign.sh)
#
# 用法: toolkit/build.sh <device.conf> <输出目录> [--profile 预设] [--with 规则] [--without 规则]
#   选补丁:默认按 device.conf(MODS 去掉 MODS_OFF);--profile/--with/--without(或同名环境变量 PROFILE/WITH/WITHOUT)
#           改选择,规则写法和依赖处理见 toolkit/lib/select.sh。选择结果写进 <输出目录>/SELECTION.txt
#   环境变量: ONLY=补丁,文件夹   在选择结果里只跑这些(调试用,出来的东西不能刷,不打包)
#             KEEP_TREE=1      构建完保留工作树($OUT/tree),方便和别的版本对比
#             SURVEY=1         换底包摸底:补丁失败不停,跑完全部后汇总哪些失败(不打包)
#             IMAGE_FLAVOR=_x  覆盖产物名后缀(默认按选择算 _optional/_debug);自用变种设 _bebug 让版本号显示成 bebug。空串 = 无后缀
#
# 输出目录里:
#   system/<IMAGE_NAME>.img、system/vbmeta_system.img        system 分区和配套的 vbmeta_system
#   firmware/boot.img、vbmeta.img、init_boot.img、vendor_boot.img   boot 集(后两个原厂原样)
#   SELECTION.txt(也拷进 system/ 和 firmware/)、MODULES.txt、SHA256SUMS、logs/
# 9008 刷机包用 toolkit/build-9008.sh(先跑本脚本,再打包)。
#
# 给补丁的环境(apply.sh / part.sh 里能用的):TREE SYS(system 树)、FW_OUT(固件目录,boot 补丁把 boot.img 写这里)、
#   MOD MOD_NAME WORK BUILD_STATE TOOLKIT REPO DEVICE_DIR CONF,以及 device.conf / conf.d 里的全部变量。
#
# device.conf 必须定义: VERSION BASE_GSI MODS(数组) SYSTEM_PART_SIZE AVBTOOL AVB_KEY_SYSTEM STOCK_FW_DIR
# 可选: BASE_GSI_SHA256(底包 sha256,对不上只警告)、STOCK_VBMETA_SYSTEM + AVB_KEY_VBMETA_SYSTEM(给了才出 vbmeta_system)、
#       FW_BOOT_EXPECT_SHA256 FW_VBMETA_EXPECT_SHA256(结果对不上就失败;boot 只在改 boot 的补丁是默认那套时核对)
set -euo pipefail

[[ $# -ge 2 ]] || { sed -n '2,24p' "$0"; exit 1; }
CONF=$(realpath "$1"); OUT=$(realpath -m "$2"); shift 2
TOOLKIT=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$TOOLKIT")
DEVICE_DIR=$(dirname "$CONF")
# shellcheck disable=SC1090
source "$CONF"
: "${VERSION:?}" "${BASE_GSI:?}" "${SYSTEM_PART_SIZE:?}" "${AVBTOOL:?}" "${AVB_KEY_SYSTEM:?}" "${STOCK_FW_DIR:?}"
[[ ${#MODS[@]} -gt 0 ]] || { echo "device.conf 没有 MODS"; exit 1; }
source "$TOOLKIT/lib/select.sh"
select_args "$@"; (( ${#SEL_REST[@]} == 0 )) || { echo "不认识的参数: ${SEL_REST[*]}"; exit 1; }
select_resolve || exit 1
# 改 boot 的补丁(STAGE=firmware/both):默认那套和这次选的,用来决定核不核对 FW_BOOT_EXPECT_SHA256
fw_of() { local m; for m in "$@"; do [[ $(_sel_stage "$m") == system ]] || echo "$m"; done; }
FW_DEFAULT=$(fw_of $(for m in "${MODS[@]}"; do _sel_in "$m" "${MODS_OFF[@]}" || echo "$m"; done) | paste -sd' ')
MODS=("${SEL_MODS[@]}")
FW_CHOSEN=$(fw_of "${MODS[@]}" | paste -sd' ')

step() { echo; echo "==== $*"; }
# 产物名:device.conf 设了 IMAGE_PREFIX 就用 <前缀>_v<版本标签>[_optional][_debug](版本标签默认是版本号数字,make-9008.sh 里可以写成 110-beta 这类,环境变量 VERSION_LABEL)(只有 required 的构建没有后缀),否则用 IMAGE_NAME
if [[ -n ${IMAGE_PREFIX:-} ]]; then
    [[ $VERSION =~ ^V([0-9]+) ]] || { echo "VERSION=$VERSION 取不出版本号"; exit 1; }
    _lab=${VERSION_LABEL:-${BASH_REMATCH[1]}}; [[ $_lab == [0-9]* ]] && _lab=v$_lab   # 数字开头加 v(v110、v110-beta),字母开头原样(test-v1)
    # 后缀默认按 select_flavor 算(_optional/_debug);环境变量 IMAGE_FLAVOR 显式覆盖(连空串也认,用 ${x-default} 不是 :-)。
    # 用途:cust-bebug 等自用变种选了 optional+debug 补丁,select_flavor 会算成 _optional_debug,但想让版本号(IMAGE_NAME,
    # 会烤进 ro.build.display.id)显示成自定的 _bebug —— 设 IMAGE_FLAVOR=_bebug 即可,版本号和包名一致。
    IMAGE_NAME=${IMAGE_PREFIX}_${_lab}${IMAGE_FLAVOR-$(select_flavor)}
fi
NAME=${IMAGE_NAME:-system_${VERSION}}
TREE=$OUT/tree
FW_OUT=$OUT/firmware
SYSOUT=$OUT/system
BUILD_STATE=$OUT/state
BASEMNT=$(mktemp -d)
cleanup() { mountpoint -q "$BASEMNT" && sudo umount "$BASEMNT"; rmdir "$BASEMNT" 2>/dev/null || true; }
trap cleanup EXIT

step "选补丁"
select_summary
(( ${#MODS[@]} )) || { echo "一个补丁都没选"; exit 1; }

step "检查输入"
[[ -f $BASE_GSI ]] || { echo "底包不存在: $BASE_GSI"; exit 1; }
if [[ -n ${BASE_GSI_SHA256:-} ]]; then
    got=$(sha256sum "$BASE_GSI" | cut -d' ' -f1)
    if [[ $got != "$BASE_GSI_SHA256" ]]; then
        echo "警告: 底包 sha256 是 $got,不是 device.conf 记录的 $BASE_GSI_SHA256"
        echo "      换了底包的话没关系,各补丁会自己检查适不适用;不是有意换的就停下来查。"
    else
        echo "底包 sha256 一致"
    fi
fi
for f in init_boot vendor_boot; do [[ -f $STOCK_FW_DIR/$f.img ]] || { echo "缺 $STOCK_FW_DIR/$f.img"; exit 1; }; done
source "$TOOLKIT/lib/runmods.sh"
check_modules "${MODS[@]}" || exit 1
mkdir -p "$OUT"
sudo rm -rf "$TREE" "$BUILD_STATE" "$OUT/work" "$FW_OUT" "$SYSOUT" "$OUT/logs"
rm -f "$OUT/SHA256SUMS" "$OUT/MODULES.txt" "$OUT/SELECTION.txt"
mkdir -p "$BUILD_STATE" "$OUT/work" "$OUT/logs" "$FW_OUT" "$SYSOUT"

step "准备工作区:GSI 底包 → $TREE(sudo cp -a 保留属主、权限、SELinux 标签),原厂固件 → $FW_OUT"
sudo mount -o loop,ro "$BASE_GSI" "$BASEMNT"
sudo mkdir -p "$TREE"
sudo cp -a "$BASEMNT/." "$TREE/"
sudo umount "$BASEMNT"
sudo test -f "$TREE/system/build.prop" || { echo "底包里没有 system/build.prop,不是 system-as-root 的 GSI?"; exit 1; }
# 底包唯一 ID(精简清单按它挑);要在 identity 改指纹之前记下来
(MOD_NAME=base-id SYS=$TREE/system; source "$TOOLKIT/lib/common.sh"; source "$TOOLKIT/lib/removelist.sh"; base_id) > "$BUILD_STATE/base-id.tmp"
mv "$BUILD_STATE/base-id.tmp" "$BUILD_STATE/base-id"
[[ -s $BUILD_STATE/base-id ]] || { echo "底包 ID 为空"; exit 1; }
echo "  底包 ID: $(cat "$BUILD_STATE/base-id")"
# init_boot / vendor_boot 原样进刷机包;boot.img 由 boot-assemble 写(没选它就没有补丁 boot,打包时用原厂的)
cp -f "$STOCK_FW_DIR/init_boot.img" "$STOCK_FW_DIR/vendor_boot.img" "$FW_OUT/"

step "依次打补丁(${#MODS[@]} 个)"
export TREE SYS=$TREE/system FW_OUT TOOLKIT REPO DEVICE_DIR BUILD_STATE VERSION IMAGE_NAME
run_mods "$OUT" "${MODS[@]}"
if (( ${#FAILED[@]} )); then
    step "摸底结果:${#FAILED[@]} 个补丁失败"
    for f in "${FAILED[@]}"; do echo "  失败: $f(日志 $OUT/logs/${f//\//__}.log)"; done
    [[ ${KEEP_TREE:-0} == 1 ]] || sudo rm -rf "$TREE"
    exit 1
fi
check_contribs || exit 1
if [[ -n ${ONLY:-} ]]; then
    echo; echo "(ONLY=$ONLY:只跑了部分补丁,不打包。工作树在 $TREE)"
    exit 0
fi

step "收尾"
if [[ -f $BUILD_STATE/sepolicy_dirty ]]; then
    # init 开机时比对这个哈希,对不上就用 secilc 重编 plat_sepolicy.cil(带 -N)。清零 = 强制重编。
    echo "0000000000000000000000000000000000000000000000000000000000000000" | sudo tee "$TREE/system/etc/selinux/plat_sepolicy_and_mapping.sha256.new" >/dev/null
    S=$TREE/system/etc/selinux/plat_sepolicy_and_mapping.sha256
    sudo chown --reference="$S" "$S.new"; sudo chmod --reference="$S" "$S.new"
    sudo python3 -I -c 'import os,sys; os.setxattr(sys.argv[2],"security.selinux",os.getxattr(sys.argv[1],"security.selinux"))' "$S" "$S.new"
    sudo mv -f "$S.new" "$S"
    echo "  plat_sepolicy_and_mapping.sha256 已清零(sepolicy 有改动)"
fi
# lost+found 不进镜像(子分区目录里的也去掉)
sudo rm -rf "$TREE/lost+found" "$TREE/system/product/lost+found" "$TREE/system/system_ext/lost+found"

step "打包 system:erofs(lz4hc;平板内核不支持 lzma)"
FINAL=$SYSOUT/$NAME.img
mkdir -p "$SYSOUT"; echo "$NAME" > "$SYSOUT/IMAGE_NAME"   # 打包脚本按它找镜像(名字带 _optional/_debug 后缀,conf 里算不出来)
sudo mkfs.erofs -zlz4hc "$FINAL" "$TREE" | tail -3
sudo chown "$(id -u):$(id -g)" "$FINAL"
size=$(stat -c %s "$FINAL")
(( size % 4096 )) && truncate -s $(( (size + 4095) / 4096 * 4096 )) "$FINAL"

step "AVB:system hashtree 签名 + vbmeta_system(分区大小固定 $SYSTEM_PART_SIZE)"
"$TOOLKIT/avb_resign.sh" system "$CONF" "$FINAL" "$SYSOUT"

step "AVB:主 vbmeta 重签"
"$TOOLKIT/avb_resign.sh" main "$CONF" "$FW_OUT"

expect() {  # expect <文件> <期望 sha256 或空>
    [[ -z ${2:-} ]] && return 0
    [[ -f $1 ]] || { echo "错误: 没有生成 $1,但 firmware.conf 记了它的 sha256"; exit 1; }
    local got; got=$(sha256sum "$1" | cut -d' ' -f1)
    if [[ $got != "$2" ]]; then
        echo "错误: $1 的 sha256 是 $got,firmware.conf 里记的是 $2"
        echo "      有意换了固件/补丁规则就把 firmware.conf 里对应的 *_EXPECT_SHA256 清空或改掉;不是有意的就停下来查。"
        exit 1
    fi
    echo "  sha256 和 firmware.conf 记录的一致: $2"
}
step "核对固件 sha256"
if [[ $FW_CHOSEN == "$FW_DEFAULT" ]]; then
    expect "$FW_OUT/boot.img" "${FW_BOOT_EXPECT_SHA256:-}"
else
    echo "  改 boot 的补丁不是默认那套($FW_CHOSEN),boot.img 和 FW_BOOT_EXPECT_SHA256 本来就对不上,不核对"
fi
expect "$FW_OUT/vbmeta.img" "${FW_VBMETA_EXPECT_SHA256:-}"

step "完成"
( cd "$OUT" && sha256sum "system/$NAME.img" $( [[ -f system/vbmeta_system.img ]] && echo system/vbmeta_system.img ) \
      $(cd "$OUT" && ls firmware/{boot,init_boot,vendor_boot,vbmeta}.img 2>/dev/null) | tee SHA256SUMS )
# 每行:补丁名 + 它的版本号(patch.conf 的 VERSION),这样镜像记录了用的是哪版补丁
: > "$OUT/MODULES.txt"
for _m in "${MODS[@]}"; do
    _v=$(sed -n 's/^VERSION=//p' "$REPO/patches/$_m/patch.conf" 2>/dev/null | head -1)
    printf '%s\t%s\n' "$_m" "${_v:-?}" >> "$OUT/MODULES.txt"
done
unset _m _v
select_record "$OUT/SELECTION.txt"
cp -f "$OUT/SELECTION.txt" "$SYSOUT/"; cp -f "$OUT/SELECTION.txt" "$FW_OUT/"
[[ ${KEEP_TREE:-0} == 1 ]] || sudo rm -rf "$TREE"
