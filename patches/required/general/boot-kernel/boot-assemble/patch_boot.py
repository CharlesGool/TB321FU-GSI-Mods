#!/usr/bin/env python3
"""从原厂 boot.img 生成补丁 boot:内核 cmdline 加参数、内核里做等长字节替换、按原签名参数重签。

用法:
  patch_boot.py --stock <原厂 boot.img> --out <输出 boot.img> --key <签名私钥.pem>
                [--cmdline "enforcing=1 selinux=1"]...        可重复,所有参数合并追加
                [--replace build-user@build-host androidbld@abfarmhost]...   可重复,FROM TO 等长
                [--salt <hex>] [--drop-duplicate-props] [--avbtool <avbtool.py>]
  --cmdline 和 --replace 至少要给一个;可以只给其中一种。

做法(每一步不满足前提就失败退出,不出半成品):
  1. 读原 boot 的 AVB footer 和 vbmeta,要求:签名有效、只有一个 hash descriptor 且名字是 boot、
     它的摘要和镜像内容对得上(说明是没动过的原厂镜像)、签名公钥等于 --key 的公钥。
  2. 按 boot header 版本解析。只认 v3/v4(cmdline 在 offset 44,长 1536 字节;页大小固定 4096,
     内核从 4096 开始),别的版本直接失败。
  3. cmdline 追加参数(所有 --cmdline 合并)。原 cmdline 里已经有同名参数、或者几次 --cmdline
     之间同名,都失败,不覆盖别人的设置。
  4. 只在内核区域 [4096, 4096+kernel_size) 里做 --replace 的等长替换。每一条命中 0 处就失败,
     不同条的命中位置重叠也失败。
  5. 重签:hash descriptor 的 salt 默认沿用原 boot 的(结果可复现),摘要重算;其余 descriptor
     原样保留;算法、rollback_index、rollback_index_location、flags、release string、分区大小都沿用。
  6. 自检:avbtool 能验过签名、公钥没变、header 参数没变、footer 之前的区域只有预期的那几处字节变了。
"""
import argparse
import hashlib
import os
import struct
import sys

sys.dont_write_bytecode = True  # 不在仓库里留 __pycache__

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.environ.get('TOOLKIT') or os.path.join(_here, '..', '..', '..', 'toolkit'), 'avb'))
import avbimg  # noqa: E402

BOOT_MAGIC = b'ANDROID!'
PAGE_V3 = 4096          # v3/v4 的 boot header 页大小固定 4096
CMDLINE_OFF, CMDLINE_LEN = 44, 1536


def die(msg):
    sys.exit(f'[boot-assemble] 错误: {msg}')


def log(msg):
    print(f'[boot-assemble] {msg}')


def parse_header(img):
    if img[:8] != BOOT_MAGIC:
        die('不是 Android boot 镜像(开头不是 ANDROID!)')
    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from('<IIII', img, 8)
    header_version, = struct.unpack_from('<I', img, 40)
    if header_version not in (3, 4):
        die(f'boot header 版本是 v{header_version},这个脚本只认 v3/v4(cmdline 位置不同,不猜)')
    expect = {3: 1580, 4: 1584}[header_version]
    if header_size != expect:
        die(f'header v{header_version} 的 header_size 应为 {expect},实际 {header_size},结构和预期不一样')
    return dict(version=header_version, kernel_size=kernel_size, ramdisk_size=ramdisk_size,
                header_size=header_size, kernel_off=PAGE_V3)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--stock', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--key', required=True)
    ap.add_argument('--cmdline', action='append', default=[], metavar='ARGS',
                    help='要追加到 cmdline 的参数(空格分隔),可重复')
    ap.add_argument('--replace', action='append', nargs=2, default=[], metavar=('FROM', 'TO'),
                    help='内核里的等长字符串替换,可重复')
    ap.add_argument('--salt', help='hash descriptor 的 salt(hex)。默认沿用原 boot 的')
    ap.add_argument('--drop-duplicate-props', action='store_true',
                    help='去掉完全重复的 property descriptor(只为和旧版 V47/V48 那颗 boot 逐字节对照用)')
    ap.add_argument('--avbtool')
    a = ap.parse_args()
    avb = avbimg.import_avbtool(a.avbtool)
    add = [t for c in a.cmdline for t in c.split()]
    if not add and not a.replace:
        die('没有任何要做的改动(--cmdline 和 --replace 都没给)')

    # ---- 1. 原 boot 的 AVB 信息 ----
    vm = avbimg.load(avb, a.stock)
    if vm.footer is None:
        die('原 boot 没有 AVB footer,没法沿用签名参数')
    if not vm.signature_ok:
        die('原 boot 的 vbmeta 签名验不过')
    hashes = [d for d in vm.descs if isinstance(d, avb.AvbHashDescriptor)]
    if len(hashes) != 1 or hashes[0].partition_name != 'boot':
        die(f'原 boot 的 descriptor 不是"一个 boot hash + 若干属性":{[avbimg.desc_name(d) for d in vm.descs]}')
    for d in vm.descs:
        if not isinstance(d, (avb.AvbHashDescriptor, avb.AvbPropertyDescriptor)):
            die(f'原 boot 带了不认识的 descriptor {avbimg.desc_name(d)},不处理')
    hd = hashes[0]
    orig_size = vm.footer.original_image_size
    if hd.image_size != orig_size:
        die(f'hash descriptor 的 image_size {hd.image_size} 和 footer 的 original_image_size {orig_size} 不一致')
    if avbimg.hash_of(avb, a.stock, hd.salt, hd.image_size, hd.hash_algorithm) != hd.digest:
        die('原 boot 的 AVB 摘要和内容对不上:输入不是没动过的原厂 boot(可能已经打过补丁)')
    key_pub = avbimg.pubkey(avb, a.key)
    if key_pub != vm.pub:
        die(f'原 boot 是公钥 sha1 {avbimg.sha1(vm.pub)} 签的,--key 的公钥是 {avbimg.sha1(key_pub)}。'
            '换 key 重签后主 vbmeta 里 boot 的 chain descriptor 就对不上了')
    log(f'原 boot: {os.path.getsize(a.stock)} 字节,内容 {orig_size} 字节,{vm.alg_name},'
        f'公钥 sha1 {avbimg.sha1(vm.pub)},rollback_index={vm.header.rollback_index},flags={vm.header.flags}')

    with open(a.stock, 'rb') as f:
        img = bytearray(f.read(orig_size))
        file_size = f.seek(0, 2)
    if file_size != vm.file_size:
        die('读文件时大小变了')

    # ---- 2. header ----
    h = parse_header(img)
    k0, k1 = h['kernel_off'], h['kernel_off'] + h['kernel_size']
    if k1 > orig_size:
        die(f'kernel_size {h["kernel_size"]} 超出镜像内容范围')
    log(f'boot header v{h["version"]},kernel {h["kernel_size"]} 字节 @ {k0},ramdisk {h["ramdisk_size"]} 字节')

    # ---- 3. cmdline ----
    if add:
        raw = bytes(img[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN])
        cur = raw.split(b'\0', 1)[0].decode('ascii', 'strict')
        if raw[len(cur):].strip(b'\0'):
            die('cmdline 字段在结尾 NUL 之后还有非零字节,结构和预期不一样')
        add_keys = [t.split('=', 1)[0] for t in add]
        dup = sorted({k for k in add_keys if add_keys.count(k) > 1})
        if dup:
            die(f'要追加的参数里 {dup} 出现了不止一次(两个模块都在设同一个参数?)')
        cur_keys = {t.split('=', 1)[0] for t in cur.split()}
        clash = [t for t in add if t.split('=', 1)[0] in cur_keys]
        if clash:
            die(f'原 cmdline "{cur}" 里已经有 {clash} 的同名参数。可能是已经打过补丁的 boot,也可能厂商另有设置,先人工看')
        new = ' '.join(cur.split() + add)
        if len(new) >= CMDLINE_LEN:
            die(f'新 cmdline 太长({len(new)} 字节,上限 {CMDLINE_LEN - 1})')
        img[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN] = new.encode('ascii').ljust(CMDLINE_LEN, b'\0')
        log(f'cmdline: "{cur}" -> "{new}"')

    # ---- 4. 内核里的等长替换 ----
    # 所有命中都先在原始内核上找好,再统一替换;不同条之间不能重叠,也不会出现"前一条的结果被后一条再替换"。
    plan = []   # (offset, from_bytes, to_bytes)
    for sfrom, sto in a.replace:
        fr, to = sfrom.encode(), sto.encode()
        if not fr or fr == to:
            die(f'替换规则 "{sfrom}" -> "{sto}" 无意义(空串或前后相同)')
        if len(fr) != len(to):
            die(f'"{sfrom}" 和 "{sto}" 长度不同,不能等长替换(会挪动内核里的偏移)')
        hits, i = [], k0
        while True:
            i = img.find(fr, i, k1)
            if i < 0:
                break
            hits.append(i)
            i += len(fr)
        if not hits:
            die(f'内核里找不到 "{sfrom}"。内核可能是压缩的,或者这个字符串本来就不在,先人工看 /proc/version 那串')
        outside = img.count(fr) - len(hits)
        log(f'内核替换 "{sfrom}" -> "{sto}":命中 {len(hits)} 处 @ {hits}'
            + (f'(内核区域外另有 {outside} 处,没动)' if outside else ''))
        plan += [(i, fr, to) for i in hits]
    plan.sort()
    for (o1, f1, _), (o2, _, _) in zip(plan, plan[1:]):
        if o1 + len(f1) > o2:
            die(f'两条替换规则在内核 @ {o2} 处重叠,规则互相冲突')
    for o, fr, to in plan:
        img[o:o + len(to)] = to
    allowed = set(range(CMDLINE_OFF, CMDLINE_OFF + CMDLINE_LEN)) if add else set()
    for o, fr, _ in plan:
        allowed.update(range(o, o + len(fr)))

    # ---- 5. 重签 ----
    salt = bytes.fromhex(a.salt) if a.salt else hd.salt
    nh = avb.AvbHashDescriptor()
    nh.image_size = orig_size
    nh.hash_algorithm = hd.hash_algorithm
    nh.partition_name = hd.partition_name
    nh.salt = salt
    nh.flags = hd.flags
    nh.digest = hashlib.new(hd.hash_algorithm, salt + bytes(img)).digest()
    descs, seen = [], set()
    for d in vm.descs:
        if d is hd:
            descs.append(nh)
            continue
        enc = bytes(d.encode())
        if a.drop_duplicate_props and enc in seen:
            log(f'去掉重复的 {avbimg.desc_name(d)}')
            continue
        seen.add(enc)
        descs.append(d)
    blob = avbimg.sign(avb, vm, descs, a.key)
    vb_off = vm.footer.vbmeta_offset
    if vb_off != (orig_size + 4095) // 4096 * 4096:
        die(f'原 boot 的 vbmeta_offset {vb_off} 不是"内容按 4096 对齐之后",布局和 avbtool 的不一样')
    if vb_off + len(blob) > file_size - 4096:
        die('新 vbmeta 放不下')
    footer = avb.AvbFooter()
    footer.original_image_size = orig_size
    footer.vbmeta_offset = vb_off
    footer.vbmeta_size = len(blob)
    out = bytearray(file_size)
    out[:orig_size] = img
    out[vb_off:vb_off + len(blob)] = blob
    out[file_size - avb.AvbFooter.SIZE:] = footer.encode()
    tmp = a.out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(out)

    # ---- 6. 自检 ----
    nv = avbimg.load(avb, tmp)
    problems = []
    if not nv.signature_ok:
        problems.append('签名验不过')
    if nv.pub != vm.pub:
        problems.append('公钥变了')
    problems += avbimg.same_header_params(vm, nv)
    if avbimg.hash_of(avb, tmp, salt, orig_size, hd.hash_algorithm) != nh.digest:
        problems.append('摘要和内容对不上')
    with open(a.stock, 'rb') as f:
        old = f.read(orig_size)
    diffs, step = [], 1 << 16
    for c in range(0, orig_size, step):
        if old[c:c + step] != out[c:c + step]:
            diffs += [i for i in range(c, min(c + step, orig_size)) if old[i] != out[i]]
    changed = len(diffs)
    stray = [i for i in diffs if i not in allowed]
    if stray:
        problems.append(f'预期之外的字节变化 {len(stray)} 处,第一处 @ {stray[0]}')
    if problems:
        os.remove(tmp)
        die('自检失败: ' + '; '.join(problems))
    os.replace(tmp, a.out)
    sha = hashlib.sha256(out).hexdigest()
    log(f'自检通过:footer 之前只变了 {changed} 字节(cmdline {"改" if add else "未动"},内核替换 {len(plan)} 处)')
    log(f'写出 {a.out}  sha256 {sha}')


if __name__ == '__main__':
    main()
