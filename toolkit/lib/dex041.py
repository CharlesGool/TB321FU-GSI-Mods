#!/usr/bin/env python3
"""DEX 041 容器格式的辅助工具(给 toolkit/lib/dex041.sh 用)。

Android 17 QPR(DP11 起)的 framework.jar / services.jar 里,classes.dex 是 **DEX 041 容器**:一个文件里
首尾相接放了好几段完整 dex(各有 0x78 字节的头,头里多了 container_size / header_offset),
**各段的偏移都是相对整个容器的绝对偏移**,字符串池等数据段共享。apktool(baksmali)/dex2jar 只认第一段,
其余各段的类全看不见(framework.jar 39282 类只能看到 7380)。

  check <jar>                         classes.dex 是 041 容器 → 退出码 0,否则 1(不存在/不是 041 也是 1)
  count <jar>                         打印 jar 里所有 classes*.dex 的类总数(041 容器逐段相加)
  repack <原jar> <R8输出目录> <输出jar>
      把 R8(D8)转出的标准 classes*.dex 换进去:原 jar 的非 dex 条目按原顺序、原属性照抄,
      dex 条目全部 stored、沿用原 classes.dex 的 external_attr。写完核对类总数与原 jar 一致。
"""
import os
import re
import struct
import sys
import zipfile

DEX = re.compile(r'^classes\d*\.dex$')


def die(msg):
    print(f'dex041: 错误: {msg}', file=sys.stderr)
    sys.exit(1)


def dex_classes(data):
    """返回一段/一个容器里的类总数(041 容器逐段累加)。"""
    total, off = 0, 0
    while off < len(data):
        if data[off:off + 4] != b'dex\n':
            break
        fs = struct.unpack_from('<I', data, off + 32)[0]
        total += struct.unpack_from('<I', data, off + 96)[0]
        if data[off + 4:off + 7] != b'041' or fs == 0:
            break
        off += fs
    return total


def jar_dexes(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if DEX.match(n)}


def is_041(path):
    try:
        with zipfile.ZipFile(path) as z:
            return z.read('classes.dex')[:8] == b'dex\n041\x00'
    except (KeyError, zipfile.BadZipFile, FileNotFoundError):
        return False


def count(path):
    return sum(dex_classes(d) for d in jar_dexes(path).values())


def repack(orig, dexdir, out):
    new = sorted((n for n in os.listdir(dexdir) if DEX.match(n)),
                 key=lambda n: int(n[7:-4] or 1))
    if not new:
        die(f'{dexdir} 里没有 classes*.dex')
    want = count(orig)
    with zipfile.ZipFile(orig) as zi, zipfile.ZipFile(out, 'w') as zo:
        attr = None
        for i in zi.infolist():
            if DEX.match(i.filename):
                if attr is None:
                    attr = i.external_attr
                continue
            zo.writestr(i, zi.read(i), compress_type=i.compress_type)
        for n in new:
            info = zipfile.ZipInfo(n, date_time=(2008, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = attr if attr is not None else 0o644 << 16
            with open(os.path.join(dexdir, n), 'rb') as f:
                zo.writestr(info, f.read())
    got = count(out)
    if got != want:
        die(f'转换后类数 {got} != 原 jar {want}')
    print(f'dex041: {os.path.basename(orig)} 041 容器 → {len(new)} 个标准 dex,共 {got} 类(与原容器一致)')


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == 'check':
        sys.exit(0 if is_041(a[1]) else 1)
    if len(a) == 2 and a[0] == 'count':
        print(count(a[1]))
        return
    if len(a) == 4 and a[0] == 'repack':
        repack(a[1], a[2], a[3])
        return
    sys.exit(__doc__)


if __name__ == '__main__':
    main()
