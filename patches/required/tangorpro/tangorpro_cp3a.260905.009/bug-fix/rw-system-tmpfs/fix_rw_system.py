#!/usr/bin/env python3
"""让 rw-system.sh 只在相机库确实需要改时才做 tmpfs 复制 + bind.

phh 的 rw-system.sh 会把 /vendor/lib{,64}/hw/com.qti.chi.override.so 和 /vendor/lib{,64}/libVD* 复制到 /mnt/phh(tmpfs),
用 sed 把 ro.product.manufacturer/brand/model 换成 sys.phh.xx.*, 再 bind 回 /vendor。
TB321FU(ZUI 17.5.10.170)的 com.qti.chi.override.so 里根本没有这三个字符串, sed 什么都不改,
结果只是多出一个从可写 tmpfs bind 到 /vendor 的挂载(检测软件会报 SYSTEM_PARTITION_WRITABLE /
ACTIVE_STACKED_FS_OVER_SYSTEM fs=tmpfs)。这里在循环里加一行: 文件里没有这些字符串就跳过。
其他需要这个处理的设备行为不变。原地改写文件, 保留属主/权限/SELinux 标签.

用法: fix_rw_system.py <system/bin/rw-system.sh>
"""
import sys

ANCHOR = (
    "for f in /vendor/lib{,64}/hw/com.qti.chi.override.so /vendor/lib{,64}/libVD*;do\n"
    "    [ ! -f $f ] && continue\n"
)
INSERT = (
    "    # TB321FU: 库里没有要替换的属性名时不复制到 tmpfs 再 bind(原来 sed 不改任何内容, 只多一个可写挂载)\n"
    "    grep -qE 'ro\\.product\\.(manufacturer|brand|model)' \"$f\" || continue\n"
)

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
if text.count(ANCHOR) != 1:
    sys.exit(f"anchor found {text.count(ANCHOR)} times, expected 1")
if INSERT in text:
    sys.exit("already patched")
text = text.replace(ANCHOR, ANCHOR + INSERT)
with open(path, "r+", encoding="utf-8") as f:
    f.seek(0)
    f.write(text)
    f.truncate()
print("  rw-system.sh: com.qti.chi.override.so / libVD* 只在含有 ro.product.* 时才复制到 tmpfs")
