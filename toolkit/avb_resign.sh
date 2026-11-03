#!/usr/bin/env bash
# AVB 重签:打完所有补丁之后的收尾步骤。不是"改动",所以不是模块,由两个 make 脚本在最后调用。
#
# 用法:
#   toolkit/avb_resign.sh main   <device.conf> <固件输出目录>             重签主 vbmeta → <目录>/vbmeta.img
#                                (toolkit/build.sh 在全部补丁之后调用)
#   toolkit/avb_resign.sh system <device.conf> <system.img> <输出目录>    给 system 镜像加 hashtree 签名,
#                                并生成配套的 <输出目录>/vbmeta_system.img
#                                (toolkit/build.sh 在 erofs 打好后调用)
#
# 为什么要有这一步:没有任何分区的内容被"改"在 vbmeta 里,只是别的分区变了,vbmeta 里钉的摘要要跟着重算、重签。
#   main    原厂 vbmeta 钉着 dtbo/init_boot/vendor_boot 的内容摘要(boot、vbmeta_system 只钉公钥)。
#           实际要刷的分区和原厂不一样(CRACKED 固件改了 vendor_boot)就必须重算,否则锁不了 BL。
#   system  system 的 hashtree 根摘要每版都变,vbmeta_system 里钉着它,要换成新镜像 footer 里那份再重签。
# 原理、签名链和踩过的坑见 docs/AVB-RESIGN.md。
#
# device.conf(含 conf.d/*.conf)要定义:
#   main:   AVBTOOL AVB_KEY_VBMETA FW_VBMETA_STOCK FW_VBMETA_IMAGES(数组)  可选 FW_BOOT_STOCK(没有补丁 boot 时用它核对 chain)
#   system: AVBTOOL SYSTEM_PART_SIZE AVB_KEY_SYSTEM  可选 STOCK_VBMETA_SYSTEM + AVB_KEY_VBMETA_SYSTEM(给了才出 vbmeta_system)
set -euo pipefail

TOOLKIT=$(cd "$(dirname "$0")" && pwd)
[[ $# -ge 3 ]] || { sed -n '2,12p' "$0"; exit 1; }
MODE=$1; CONF=$(realpath "$2"); shift 2
REPO=$(dirname "$TOOLKIT"); DEVICE_DIR=$(dirname "$CONF")
export REPO DEVICE_DIR
# shellcheck disable=SC1090
source "$CONF"
: "${AVBTOOL:?device.conf 没设 AVBTOOL}"
need() { [[ -f ${!1:-} ]] || { echo "avb_resign: 缺输入 $1=${!1:-(未设置)}"; exit 1; }; }

case $MODE in
main)
    OUT=$(realpath -m "$1")
    : "${AVB_KEY_VBMETA:?}" "${FW_VBMETA_STOCK:?在 firmware.conf 里设置}"
    need FW_VBMETA_STOCK; need AVB_KEY_VBMETA
    [[ ${#FW_VBMETA_IMAGES[@]} -gt 0 ]] || { echo "FW_VBMETA_IMAGES 是空的(在 firmware.conf 里列出主 vbmeta 各 descriptor 对应的分区文件)"; exit 1; }
    # boot 是 chain descriptor,只核对签名公钥:用刚生成的补丁 boot;没启用任何 boot 补丁时用原厂 boot
    if [[ -f $OUT/boot.img ]]; then BOOT=$OUT/boot.img
    elif [[ -n ${FW_BOOT_STOCK:-} && -f $FW_BOOT_STOCK ]]; then BOOT=$FW_BOOT_STOCK; echo "avb_resign: 没有补丁 boot,用原厂 boot 核对 chain"
    else echo "avb_resign: $OUT/boot.img 不存在,也没有 FW_BOOT_STOCK"; exit 1; fi
    args=(--vbmeta "$FW_VBMETA_STOCK" --out "$OUT/vbmeta.img" --key "$AVB_KEY_VBMETA" --avbtool "$AVBTOOL" --image "boot=$BOOT")
    for i in "${FW_VBMETA_IMAGES[@]}"; do args+=(--image "$i"); done
    python3 -I "$TOOLKIT/avb/resign_vbmeta.py" "${args[@]}"
    ;;
system)
    IMG=$(realpath "$1"); OUT=$(realpath -m "$2")
    : "${SYSTEM_PART_SIZE:?}" "${AVB_KEY_SYSTEM:?}"
    [[ -f $IMG ]] || { echo "avb_resign: system 镜像不存在: $IMG"; exit 1; }
    # 分区大小必须和 super 里 system_a 的大小一致。按镜像大小自动算会漂 ±4096,AVB footer 落错位置(V57 踩过)。
    max=$(python3 -I "$AVBTOOL" add_hashtree_footer --partition_size "$SYSTEM_PART_SIZE" --do_not_generate_fec --calc_max_image_size)
    size=$(stat -c %s "$IMG")
    (( max >= size )) || { echo "镜像 $size 字节,超过分区能放的 $max 字节"; exit 1; }
    python3 -I "$AVBTOOL" add_hashtree_footer --image "$IMG" --partition_name system --partition_size "$SYSTEM_PART_SIZE" \
        --key "$AVB_KEY_SYSTEM" --algorithm SHA256_RSA4096 --hash_algorithm sha256 --do_not_generate_fec
    [[ $(stat -c %s "$IMG") == "$SYSTEM_PART_SIZE" ]] || { echo "签名后大小不等于分区大小"; exit 1; }
    mkdir -p "$OUT/verify"; ln -sf "$IMG" "$OUT/verify/system.img"
    python3 -I "$AVBTOOL" verify_image --image "$OUT/verify/system.img" --key "$AVB_KEY_SYSTEM" | tail -2
    if [[ -n ${STOCK_VBMETA_SYSTEM:-} ]]; then
        : "${AVB_KEY_VBMETA_SYSTEM:?}"
        echo "vbmeta_system:沿用原厂的其它 descriptor,只换 system 的 hashtree,重签"
        python3 -I "$TOOLKIT/avb/mk_vbmeta_system.py" "$STOCK_VBMETA_SYSTEM" "$IMG" "$OUT/vbmeta_system.img" "$AVB_KEY_VBMETA_SYSTEM" "$AVBTOOL"
    fi
    ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
