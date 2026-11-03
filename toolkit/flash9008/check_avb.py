#!/usr/bin/env python3
"""按"刷完之后设备上的样子"核对整条 AVB 链,不用真的拼出 super。

用法:
  check_avb.py --xml <新 LUN0 rawprogram XML> --dir <目录>... [--file 名字=路径 ...]
               --vbmeta <vbmeta.img> --vbmeta-system <vbmeta_system.img>
               [--part 分区名=镜像 ...] [--strict] [--avbtool <avbtool.py>]

  --dir    找 XML 里 super 分片文件、以及 dtbo/pvmfw/recovery 等单独分区镜像的目录(按顺序找)
  --file   XML 里某个分片文件名实际在哪(比如 super_4_v66.img=/x/system.img)
  --part   单独分区(boot/init_boot/vendor_boot/dtbo…)用哪个镜像,优先于 --dir 里同名的 <分区>.img

核对内容(从 vbmeta 开始往下):
  chain descriptor     被 chain 的镜像(boot、vbmeta_system…)签名有效,且公钥 = chain 里钉的公钥
  hash descriptor      H(salt || 镜像前 image_size 字节) = 摘要
  hashtree descriptor  super 里对应逻辑分区(<名字>_a)末尾 AVB footer 里的同名 descriptor 和这里逐字节相同
  vbmeta flags         必须是 0(flags=2 的 vbmeta 在 TB321FU 上会被 ABL 拒)
找不到镜像的分区记为"未核对";--strict 时未核对也算失败。任何"对不上"都失败。
"""
import argparse
import hashlib
import os
import sys

sys.dont_write_bytecode = True  # 不在仓库里留 __pycache__

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from superview import SuperView, SuperError  # noqa: E402


def load_avbtool(path):
    path = os.path.abspath(path or os.path.join(HERE, '..', 'avb', 'avbtool.py'))
    sys.path.insert(0, os.path.dirname(path))
    import avbtool
    return avbtool


def parse_vbmeta(avb, read, total):
    """read(off, n) 读镜像;total 是镜像总长。返回 (header, blob, descs, pub)。"""
    off = 0
    try:
        ft = avb.AvbFooter(read(total - avb.AvbFooter.SIZE, avb.AvbFooter.SIZE))
        off = ft.vbmeta_offset
    except Exception:
        pass
    h = avb.AvbVBMetaHeader(read(off, avb.AvbVBMetaHeader.SIZE))
    blob = read(off, avb.AvbVBMetaHeader.SIZE + h.authentication_data_block_size + h.auxiliary_data_block_size)
    aux = avb.AvbVBMetaHeader.SIZE + h.authentication_data_block_size
    descs = avb.parse_descriptors(blob[aux + h.descriptors_offset: aux + h.descriptors_offset + h.descriptors_size])
    pub = blob[aux + h.public_key_offset: aux + h.public_key_offset + h.public_key_size]
    return h, blob, descs, pub


def file_reader(path):
    def read(off, n):
        with open(path, 'rb') as f:
            f.seek(off)
            return f.read(n)
    return read, os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--xml', required=True)
    ap.add_argument('--dir', action='append', default=[])
    ap.add_argument('--file', action='append', default=[])
    ap.add_argument('--part', action='append', default=[])
    ap.add_argument('--vbmeta', required=True)
    ap.add_argument('--vbmeta-system', required=True)
    ap.add_argument('--strict', action='store_true')
    ap.add_argument('--avbtool')
    a = ap.parse_args()
    avb = load_avbtool(a.avbtool)
    override = dict(s.split('=', 1) for s in a.file)
    parts = dict(s.split('=', 1) for s in a.part)
    parts['vbmeta'], parts['vbmeta_system'] = a.vbmeta, a.vbmeta_system
    sv = SuperView(a.xml, a.dir, override)

    fails, unchecked = [], []

    def bad(m):
        fails.append(m)
        print(f'  不符  {m}')

    def ok(m):
        print(f'  通过  {m}')

    def image_of(name):
        if name in parts:
            return parts[name]
        for d in a.dir:
            p = os.path.join(d, name + '.img')
            if os.path.isfile(p):
                return p
        return None

    def walk(label, read, total, expect_pub=None):
        h, blob, descs, pub = parse_vbmeta(avb, read, total)
        alg = avb.lookup_algorithm_by_type(h.algorithm_type)[0]
        print(f'== {label}: {alg},公钥 sha1 {hashlib.sha1(pub).hexdigest()[:8]},flags={h.flags},'
              f'rollback_index={h.rollback_index}')
        if not avb.verify_vbmeta_signature(h, blob):
            bad(f'{label} 签名无效')
        if expect_pub is not None and pub != expect_pub:
            bad(f'{label} 的签名公钥和上级 chain 钉的不一样')
        if h.flags != 0:
            bad(f'{label} flags={h.flags}(要 0)')
        for d in descs:
            n = getattr(d, 'partition_name', None)
            if isinstance(d, avb.AvbChainPartitionDescriptor):
                p = image_of(n)
                if not p:
                    unchecked.append(n)
                    print(f'  未核对 chain {n}(没有镜像)')
                    continue
                r, t = file_reader(p)
                walk(f'{n}({os.path.basename(p)})', r, t, d.public_key)
            elif isinstance(d, avb.AvbHashDescriptor):
                p = image_of(n)
                if not p:
                    unchecked.append(n)
                    print(f'  未核对 hash {n}(没有镜像)')
                    continue
                hh = hashlib.new(d.hash_algorithm, d.salt)
                with open(p, 'rb') as f:
                    left = d.image_size
                    while left:
                        c = f.read(min(left, 16 << 20))
                        if not c:
                            break
                        hh.update(c)
                        left -= len(c)
                if hh.digest() == d.digest:
                    ok(f'hash {n} = {d.digest.hex()[:16]}…({os.path.basename(p)})')
                else:
                    bad(f'hash {n}: 镜像 {os.path.basename(p)} 算出 {hh.hexdigest()[:16]}…,{label} 里钉的是 {d.digest.hex()[:16]}…')
            elif isinstance(d, avb.AvbHashtreeDescriptor):
                ln = n + '_a'
                if ln not in sv.parts:
                    unchecked.append(n)
                    print(f'  未核对 hashtree {n}(super 里没有 {ln})')
                    continue
                po, pl = sv.parts[ln]
                try:
                    _, _, pd, _ = parse_vbmeta(avb, lambda o, k: sv.read(po + o, k), pl)
                except SuperError as e:
                    bad(f'hashtree {n}: 读不到分区末尾的 AVB footer({e})')
                    continue
                except Exception:
                    bad(f'hashtree {n}: super 里 {ln} 末尾没有 AVB footer(分区大小和镜像对不上?)')
                    continue
                mine = [x for x in pd if isinstance(x, avb.AvbHashtreeDescriptor) and x.partition_name == n]
                if len(mine) == 1 and bytes(mine[0].encode()) == bytes(d.encode()):
                    ok(f'hashtree {n} root {d.root_digest.hex()[:16]}…(super 里 {ln})')
                else:
                    got = mine[0].root_digest.hex()[:16] if mine else '无'
                    bad(f'hashtree {n}: super 里 {ln} 是 {got}…,{label} 里钉的是 {d.root_digest.hex()[:16]}…')

    r, t = file_reader(a.vbmeta)
    walk('vbmeta', r, t)
    print()
    if unchecked:
        print(f'未核对: {", ".join(unchecked)}')
    if fails:
        sys.exit(f'[check_avb] 失败 {len(fails)} 项')
    if unchecked and a.strict:
        sys.exit('[check_avb] --strict: 有未核对的分区')
    print('[check_avb] AVB 链核对通过')


if __name__ == '__main__':
    try:
        main()
    except SuperError as e:
        sys.exit(f'[check_avb] 错误: {e}')
