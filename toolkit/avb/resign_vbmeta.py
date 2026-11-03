#!/usr/bin/env python3
"""按实际要刷的分区文件,重算主 vbmeta 里的 hash 摘要并重签(flags 等参数全部沿用原厂)。

用法:
  resign_vbmeta.py --vbmeta <原厂 vbmeta.img> --out <输出> --key <签名私钥.pem>
                   --image <分区名>=<文件> [--image ...] [--skip <分区名>] [--avbtool <avbtool.py>]

对原 vbmeta 里的每个 descriptor:
  hash(dtbo/init_boot/vendor_boot…)  必须给 --image。摘要按 H(salt || 文件前 image_size 字节) 重算,
                                     salt 沿用原值。文件自己带 AVB footer 时 image_size 取 footer 里的
                                     original_image_size。只有摘要(和 image_size)会变。
  hashtree(vendor/odm/…,在 super 里) 必须给 --image(或 --skip)。读文件自己 AVB footer 里的同名 hashtree
                                     descriptor,和 vbmeta 里的逐字节比。不一致就失败——这种情况说明逻辑
                                     分区被改过,要换整个 descriptor,这个脚本不替你做决定。
  chain(boot/recovery/vbmeta_system) 给了 --image 就核对该镜像的签名公钥等于 chain 里钉的公钥;不给只提示。
  property                           原样保留。

签名参数(算法、rollback_index、rollback_index_location、flags、release string)全部沿用原 vbmeta。
flags 原来不是 0 会直接失败:flags=2(关校验)的主 vbmeta 在 TB321FU 上会被 ABL 拒(V6 期间实测)。
输出补零到原文件大小。最后自检:签名有效、header 参数没变、只有预期的 descriptor 变了。
"""
import argparse
import hashlib
import os
import sys

sys.dont_write_bytecode = True  # 不在仓库里留 __pycache__

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _here)
import avbimg  # noqa: E402


def die(msg):
    sys.exit(f'[avb_resign] 错误: {msg}')


def log(msg):
    print(f'[avb_resign] {msg}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--vbmeta', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--key', required=True)
    ap.add_argument('--image', action='append', default=[], metavar='NAME=FILE')
    ap.add_argument('--skip', action='append', default=[], metavar='NAME',
                    help='不核对这个 hashtree/chain 分区(必须显式写出来)')
    ap.add_argument('--allow-flags', action='store_true', help='原 vbmeta flags 不是 0 也继续(别用)')
    ap.add_argument('--avbtool')
    a = ap.parse_args()
    avb = avbimg.import_avbtool(a.avbtool)

    imgs = {}
    for s in a.image:
        if '=' not in s:
            die(f'--image 要写成 名字=文件: {s}')
        n, p = s.split('=', 1)
        if not os.path.isfile(p):
            die(f'{n} 的文件不存在: {p}')
        imgs[n] = p

    vm = avbimg.load(avb, a.vbmeta)
    if vm.footer is not None:
        die('输入带 AVB footer,这是分区镜像不是主 vbmeta')
    if not vm.signature_ok:
        die('原 vbmeta 签名验不过')
    if vm.header.flags != 0 and not a.allow_flags:
        die(f'原 vbmeta flags={vm.header.flags}。主 vbmeta 要 flags=0 才能锁 BL(flags=2 会被 ABL 拒),先换一份原厂 vbmeta')
    key_pub = avbimg.pubkey(avb, a.key)
    if key_pub != vm.pub:
        die(f'原 vbmeta 是公钥 sha1 {avbimg.sha1(vm.pub)} 签的,--key 是 {avbimg.sha1(key_pub)}。'
            'ABL 只认设备里烧的那把根公钥,换 key 必砖')
    log(f'原 vbmeta: {vm.alg_name},公钥 sha1 {avbimg.sha1(vm.pub)},rollback_index={vm.header.rollback_index},'
        f'flags={vm.header.flags},{len(vm.descs)} 个 descriptor')

    used, changed, out = set(), [], []
    for d in vm.descs:
        name = getattr(d, 'partition_name', None)
        if isinstance(d, avb.AvbHashDescriptor):
            if name not in imgs:
                die(f'vbmeta 里有 {name} 的 hash descriptor,没给 --image {name}=…')
            used.add(name)
            p = imgs[name]
            size = d.image_size
            try:
                part = avbimg.load(avb, p)
                if part.footer is not None:
                    size = part.footer.original_image_size
            except Exception:
                part = None
            if os.path.getsize(p) < size:
                die(f'{name}: 文件 {os.path.getsize(p)} 字节,比 image_size {size} 小')
            dig = avbimg.hash_of(avb, p, d.salt, size, d.hash_algorithm)
            if dig == d.digest and size == d.image_size:
                log(f'  hash  {name:14s} 一致      {dig.hex()[:16]}…')
                out.append(d)
                continue
            nd = avb.AvbHashDescriptor(bytes(d.encode()))
            nd.image_size, nd.digest = size, dig
            log(f'  hash  {name:14s} 重算      {d.digest.hex()[:16]}… -> {dig.hex()[:16]}…'
                + (f'  (image_size {d.image_size} -> {size})' if size != d.image_size else ''))
            changed.append(name)
            out.append(nd)
        elif isinstance(d, avb.AvbHashtreeDescriptor):
            out.append(d)
            if name in a.skip:
                log(f'  tree  {name:14s} 跳过核对(--skip)')
                continue
            if name not in imgs:
                die(f'vbmeta 里有 {name} 的 hashtree descriptor,没给 --image {name}=…(确实不想核对就 --skip {name})')
            used.add(name)
            part = avbimg.load(avb, imgs[name])
            mine = [x for x in part.descs if isinstance(x, avb.AvbHashtreeDescriptor) and x.partition_name == name]
            if len(mine) != 1:
                die(f'{name}: {imgs[name]} 的 AVB footer 里没有唯一的 {name} hashtree descriptor')
            if bytes(mine[0].encode()) != bytes(d.encode()):
                die(f'{name}: 镜像自己的 hashtree descriptor 和 vbmeta 里的不一样'
                    f'(root {mine[0].root_digest.hex()[:16]}… vs {d.root_digest.hex()[:16]}…)。'
                    '这个逻辑分区被改过,要换整个 descriptor,先人工确认')
            log(f'  tree  {name:14s} 一致      {d.root_digest.hex()[:16]}…')
        elif isinstance(d, avb.AvbChainPartitionDescriptor):
            out.append(d)
            if name in imgs:
                used.add(name)
                c = avbimg.load(avb, imgs[name])
                if c.pub != d.public_key:
                    die(f'{name}: 镜像签名公钥 sha1 {avbimg.sha1(c.pub)},chain 钉的是 {avbimg.sha1(d.public_key)}')
                if not c.signature_ok:
                    die(f'{name}: 镜像自己的 vbmeta 签名验不过')
                log(f'  chain {name:14s} 公钥一致  {avbimg.sha1(d.public_key)[:8]}(rollback 槽 {d.rollback_index_location})')
            else:
                log(f'  chain {name:14s} 未核对    钉公钥 {avbimg.sha1(d.public_key)[:8]}(没给镜像)')
        elif isinstance(d, avb.AvbPropertyDescriptor):
            out.append(d)
        else:
            die(f'不认识的 descriptor {avbimg.desc_name(d)}')
    extra = set(imgs) - used
    if extra:
        die(f'给了 vbmeta 里没有的分区: {sorted(extra)}')

    blob = avbimg.sign(avb, vm, out, a.key)
    size = max(vm.file_size, (len(blob) + 4095) // 4096 * 4096)
    blob += b'\0' * (size - len(blob))
    tmp = a.out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(blob)

    nv = avbimg.load(avb, tmp)
    problems = [] if nv.signature_ok else ['签名验不过']
    if nv.pub != vm.pub:
        problems.append('公钥变了')
    problems += avbimg.same_header_params(vm, nv)
    if len(nv.descs) != len(vm.descs):
        problems.append('descriptor 个数变了')
    for x, y in zip(vm.descs, nv.descs):
        same = bytes(x.encode()) == bytes(y.encode())
        if not same and getattr(x, 'partition_name', None) not in changed:
            problems.append(f'{avbimg.desc_name(x)} 意外变了')
        if same and getattr(x, 'partition_name', None) in changed and isinstance(x, avb.AvbHashDescriptor):
            problems.append(f'{avbimg.desc_name(x)} 应该变却没变')
    if problems:
        os.remove(tmp)
        die('自检失败: ' + '; '.join(problems))
    os.replace(tmp, a.out)
    log(f'自检通过:改了 {changed or "无"},flags={nv.header.flags}')
    log(f'写出 {a.out}({size} 字节)sha256 {hashlib.sha256(blob).hexdigest()}')


if __name__ == '__main__':
    main()
