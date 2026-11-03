#!/usr/bin/env bash
# 对着一个构建好的 system 镜像,把里面的每个 overlay 用设备上同一个 idmap2(arm64,经 qemu-user)真的生成一次 idmap,
# 并列出每个 overlay 映射到了几条资源。生成失败、或者 0 条映射,就报错(退出码 1)。
#
# 用法: toolkit/check-overlays.sh <system 镜像.img>
# 需要: sudo、qemu-user-static(apt install qemu-user-static;装上会注册 ARM 的 binfmt,宿主机全局生效)。
#
# 做法:只读挂载镜像,上面叠一层 overlayfs 当 chroot 根,把镜像里的 runtime APEX(bionic 的 libc / linker)挂到 /apex/com.android.runtime,
# 用镜像自己的 /system/bin/idmap2 对镜像自己的 framework-res.apk 生成 idmap。policy 取 system+product+public(设备上 /system/product/overlay 的实际情况)。
# 局限(V69/V70 的教训):这一步在构建机上通过,不等于设备上一定有 idmap——V69/V70 的 brightness-curve 在这里能生成 5 条映射,真机上却是
# STATE_NO_IDMAP(原因待查)。所以它能挡住"零映射/资源对不上"这一类错误,挡不住设备上 /data/resource-cache 里的状态问题。
set -euo pipefail
IMG=$(realpath "${1:?用法: check-overlays.sh <system 镜像.img>}")
command -v qemu-aarch64-static >/dev/null || { echo "check-overlays: 缺 qemu-aarch64-static(sudo apt install qemu-user-static)"; exit 2; }
T=$(mktemp -d); LOW=$T/low; UP=$T/up; WK=$T/wk; ROOT=$T/root; RT=$T/rt
mkdir -p "$LOW" "$UP" "$WK" "$ROOT" "$RT"
cleanup() { for m in "$ROOT/proc" "$ROOT/apex/com.android.runtime" "$ROOT" "$LOW"; do mountpoint -q "$m" 2>/dev/null && sudo umount "$m"; done; sudo rm -rf "$T"; }
trap cleanup EXIT
sudo mount -o loop,ro "$IMG" "$LOW"
sudo mount -t overlay overlay -o "lowerdir=$LOW,upperdir=$UP,workdir=$WK" "$ROOT"
sudo unzip -q -o "$ROOT/system/apex/com.android.runtime.apex" apex_payload.img -d "$RT"
sudo mkdir -p "$ROOT/apex/com.android.runtime" "$ROOT/work" "$ROOT/proc"
sudo mount -o loop,ro "$RT/apex_payload.img" "$ROOT/apex/com.android.runtime"
sudo mount -t proc proc "$ROOT/proc"
sudo cp "$(command -v qemu-aarch64-static)" "$ROOT/work/qemu"
idmap() { sudo chroot "$ROOT" /work/qemu /system/bin/idmap2 "$@" 2>&1 | grep -v -i 'linker' || true; }
FAIL=0; N=0
printf '%-62s %s\n' overlay 映射条数
while IFS= read -r ov; do
    rel=${ov#"$ROOT"}
    # 只检查目标是 android(framework-res)的:读清单里的 targetPackage
    out=$(idmap create --target-apk-path /system/framework/framework-res.apk --overlay-apk-path "$rel" --idmap-path /work/t.idmap \
          --policy system --policy product --policy public) || true
    if [[ $out == *error* ]]; then
        # 目标不是 android 的(如 settings / systemui)会在这里报错,单独用对应目标再试一次太重,标出来由人看
        printf '%-62s %s\n' "$rel" "无法对 framework-res 生成: ${out//$'\n'/ }"
        continue
    fi
    cnt=$(idmap dump --idmap-path /work/t.idmap | grep -c -- '->' || true)
    N=$((N+1))
    printf '%-62s %s\n' "$rel" "$cnt"
    (( cnt > 0 )) || FAIL=1
    sudo rm -f "$ROOT/work/t.idmap"
done < <(sudo find "$ROOT/system/product/overlay" -name 'tb321fu-*.apk' -o -name 'treble-overlay-lenovo-tb321fu*.apk' 2>/dev/null | sort)
echo "检查了 $N 个 overlay"
(( FAIL )) && { echo "check-overlays: 有 overlay 一条资源都没映射上"; exit 1; }
exit 0
