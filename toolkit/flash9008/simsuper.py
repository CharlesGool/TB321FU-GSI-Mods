#!/usr/bin/env python3
"""按 rawprogram XML 模拟 fh_loader 写 super,再按 lp 元数据切出每个逻辑分区。

用法: simsuper.py <rawprogram XML> <输出目录> <找分片文件的目录>... [--only 分区名,…] [--check]

  --check   只做结构检查(每个分片落在哪个逻辑分区、有没有重叠/越界/空洞),不写文件
  --only    只切这几个分区(名字带不带 _a 都行)

输出 <输出目录>/<分区名去掉 _a>.img,比如 vendor.img、system.img。
不落盘整块 super(13GB),直接从分片里读,所以只占切出来的分区那么多空间。
"""
import os
import sys

sys.dont_write_bytecode = True  # 不在仓库里留 __pycache__

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lp  # noqa: E402
from superview import SuperView, SuperError  # noqa: E402


def main(argv):
    only, check = None, False
    args = []
    it = iter(argv)
    for x in it:
        if x == '--only':
            only = {n.removesuffix('_a') for n in next(it).split(',')}
        elif x == '--check':
            check = True
        else:
            args.append(x)
    if len(args) < 3:
        sys.exit(__doc__)
    xml_path, out_dir, dirs = args[0], args[1], args[2:]
    sv = SuperView(xml_path, dirs)
    print(f'super: {sv.size} 字节,起始扇区 {sv.start},扇区 {sv.ss} 字节,{len(sv.entries)} 个分片')
    covered = {}
    for e in sv.entries:
        own = sv.owner(e)
        print(f'  {e["filename"]:24s} super+{e["off"]:>12d}  {e["end"] - e["off"]:>12d} 字节  -> {own}')
        if own != '(lp 元数据)':
            covered[own] = covered.get(own, 0) + e['end'] - e['off']
    if sv.entries[0]['end'] < lp.metadata_size(lp.geometry(sv.meta)):
        raise SuperError('第一个分片装不下全部 lp 元数据')
    for n, (o, l) in sorted(sv.parts.items(), key=lambda x: x[1][0]):
        c = covered.get(n, 0)
        flag = '' if c == l else f'  (分片只覆盖 {c} 字节)'
        print(f'  分区 {n:16s} super+{o:>12d}  {l:>12d} 字节{flag}')
    if check:
        print('结构检查通过')
        return
    os.makedirs(out_dir, exist_ok=True)
    for n, (o, l) in sv.parts.items():
        base = n.removesuffix('_a')
        if only and base not in only:
            continue
        dst = os.path.join(out_dir, base + '.img')
        with open(dst, 'wb') as f:
            pos = 0
            while pos < l:
                take = min(l - pos, 16 << 20)
                f.write(sv.read(o + pos, take))
                pos += take
        print(f'切出 {n} -> {dst}')
    print('完成')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (SuperError, lp.LpError) as e:
        sys.exit(f'[simsuper] 错误: {e}')
