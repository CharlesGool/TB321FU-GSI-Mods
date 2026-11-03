#!/usr/bin/env python3
"""super 分区开头的 lp(动态分区)元数据:读、改一个逻辑分区的大小、校验。

9008 包里 super 被拆成 super_1..N.img 分片,super_1 就是 super 开头这一段:
  4096 字节保留区 + 2 份 geometry(各 4096)+ slot_count 份主元数据 + slot_count 份备份元数据
  (每份 metadata_max_size 字节)。TB321FU 是 3 slot × 65536,共 405504 字节。

用法:
  lp.py dump   <super_1.img>
  lp.py resize <super_1.img> <分区名> <新字节数> <输出>

resize 只改每份元数据里那个分区唯一 extent 的扇区数,再重算 tables 和 header 的 sha256。
只能缩小或不变:放大会和后面紧挨着的分区重叠(super 里各分区是首尾相接排的),要放大得重排整个 super,
这个工具不做,直接失败。
"""
import hashlib
import struct
import sys

GEOM_MAGIC = 0x616C4467
HDR_MAGIC = 0x414C5030
RESERVED = 4096
GEOM_SIZE = 4096
PART_FMT, EXT_FMT, GRP_FMT, BDEV_FMT = '<36sIIII', '<QIQI', '<36sIQ', '<QIIQ36sI'


class LpError(Exception):
    pass


def _need(cond, msg):
    if not cond:
        raise LpError(msg)


def geometry(buf):
    magic, struct_size = struct.unpack_from('<II', buf, RESERVED)
    _need(magic == GEOM_MAGIC, f'geometry magic 不对: {magic:#x}(不是 super 开头那一段?)')
    max_size, slots, lbs = struct.unpack_from('<III', buf, RESERVED + 8 + 32)
    return dict(struct_size=struct_size, metadata_max_size=max_size, slot_count=slots, logical_block_size=lbs)


def metadata_size(geo):
    """super 开头元数据区总长(= super_1 分片应有的长度)。"""
    return RESERVED + 2 * GEOM_SIZE + 2 * geo['slot_count'] * geo['metadata_max_size']


def metadata_offsets(geo):
    base = RESERVED + 2 * GEOM_SIZE
    n, m = geo['slot_count'], geo['metadata_max_size']
    return [base + i * m for i in range(n)] + [base + (n + i) * m for i in range(n)]


def parse(buf, off):
    magic, major, minor, hsize = struct.unpack_from('<IHHI', buf, off)
    _need(magic == HDR_MAGIC, f'@{off} 元数据 header magic 不对: {magic:#x}')
    tables_size, = struct.unpack_from('<I', buf, off + 44)
    descs = struct.unpack_from('<' + 'III' * 4, buf, off + 80)
    t = off + hsize

    def table(i, fmt):
        o, n, sz = descs[i * 3:(i + 1) * 3]
        _need(sz == struct.calcsize(fmt), f'表 {i} 的条目大小 {sz} 和预期不同(lp 元数据版本不认识)')
        return [(t + o + k * sz, struct.unpack_from(fmt, buf, t + o + k * sz)) for k in range(n)]

    return dict(major=major, minor=minor, header_size=hsize, tables_size=tables_size, tables_off=t,
                parts=table(0, PART_FMT), extents=table(1, EXT_FMT), groups=table(2, GRP_FMT), bdevs=table(3, BDEV_FMT))


def name(b):
    return b.split(b'\0', 1)[0].decode()


def partitions(buf, slot=0):
    """返回 [(分区名, [(字节偏移, 字节长度), ...])],偏移相对 super 开头。"""
    geo = geometry(buf)
    md = parse(buf, metadata_offsets(geo)[slot])
    out = []
    for _, (pn, attr, fe, ne, gi) in md['parts']:
        exts = []
        for k in range(ne):
            nsec, ttype, tdata, tsrc = md['extents'][fe + k][1]
            _need(ttype == 0, f'{name(pn)} 有非 linear 的 extent(类型 {ttype})')
            exts.append((tdata * 512, nsec * 512))
        out.append((name(pn), exts))
    return out


def super_size(buf):
    geo = geometry(buf)
    md = parse(buf, metadata_offsets(geo)[0])
    _need(len(md['bdevs']) == 1, 'super 由多个块设备组成,不支持')
    return md['bdevs'][0][1][3]


def dump(buf):
    geo = geometry(buf)
    print('geometry', geo)
    for i, off in enumerate(metadata_offsets(geo)):
        md = parse(buf, off)
        kind = 'primary' if i < geo['slot_count'] else 'backup'
        print(f'\n== {kind} slot {i % geo["slot_count"]} @ {off} v{md["major"]}.{md["minor"]}')
        for _, (n, align, aoff, size, pn, fl) in md['bdevs']:
            print(f'  bdev {name(pn)} first_logical_sector={n} size={size}')
        for _, (gn, fl, mx) in md['groups']:
            print(f'  group {name(gn)} max={mx}')
        for _, (pn, attr, fe, ne, gi) in md['parts']:
            exts = [md['extents'][fe + k][1] for k in range(ne)]
            desc = ', '.join(f'{e[0] * 512} bytes @ sector512 {e[2]}' for e in exts)
            print(f'  part {name(pn):16s} group={gi} attr={attr} extents: {desc}')


def resize_partition(buf, pname, new_bytes):
    """在每一份元数据里把 pname(单 extent)的大小改成 new_bytes,重算校验和。"""
    _need(new_bytes % 4096 == 0, f'新大小 {new_bytes} 不是 4096 的倍数')
    geo = geometry(buf)
    _need(len(buf) >= metadata_size(geo), f'文件只有 {len(buf)} 字节,装不下全部 {2 * geo["slot_count"]} 份元数据')
    for off in metadata_offsets(geo):
        md = parse(buf, off)
        hit = [p for p in md['parts'] if name(p[1][0]) == pname]
        _need(len(hit) == 1, f'元数据 @{off} 里没有唯一的分区 {pname}')
        _, (_, _, fe, ne, _) = hit[0]
        _need(ne == 1, f'{pname} 有 {ne} 个 extent,只支持 1 个')
        eoff, (nsec, ttype, tdata, tsrc) = md['extents'][fe]
        _need(new_bytes // 512 <= nsec,
              f'{pname} 原来 {nsec * 512} 字节,新的 {new_bytes} 更大。放大会压到后面的分区,这个工具不做')
        struct.pack_into(EXT_FMT, buf, eoff, new_bytes // 512, ttype, tdata, tsrc)
        t = md['tables_off']
        buf[off + 48:off + 80] = hashlib.sha256(bytes(buf[t:t + md['tables_size']])).digest()
        buf[off + 12:off + 44] = b'\0' * 32
        buf[off + 12:off + 44] = hashlib.sha256(bytes(buf[off:off + md['header_size']])).digest()


def verify(buf, quiet=False):
    geo = geometry(buf)
    for off in metadata_offsets(geo):
        md = parse(buf, off)
        t = md['tables_off']
        _need(bytes(buf[off + 48:off + 80]) == hashlib.sha256(bytes(buf[t:t + md['tables_size']])).digest(),
              f'@{off} tables 校验和不对')
        h = bytearray(buf[off:off + md['header_size']])
        h[12:44] = b'\0' * 32
        _need(bytes(buf[off + 12:off + 44]) == hashlib.sha256(bytes(h)).digest(), f'@{off} header 校验和不对')
    # 各份元数据内容必须一样(除了自身位置无关的部分本来就一样)
    first = parse(buf, metadata_offsets(geo)[0])
    ref = bytes(buf[first['tables_off']:first['tables_off'] + first['tables_size']])
    for off in metadata_offsets(geo)[1:]:
        md = parse(buf, off)
        _need(bytes(buf[md['tables_off']:md['tables_off'] + md['tables_size']]) == ref, f'@{off} 和第一份元数据内容不同')
    if not quiet:
        print('checksums OK in', len(metadata_offsets(geo)), 'metadata copies')


if __name__ == '__main__':
    try:
        cmd, src = sys.argv[1], sys.argv[2]
        data = bytearray(open(src, 'rb').read())
        if cmd == 'dump':
            verify(data)
            dump(data)
        elif cmd == 'resize':
            part, size, dst = sys.argv[3], int(sys.argv[4]), sys.argv[5]
            verify(data)
            resize_partition(data, part, size)
            verify(data)
            open(dst, 'wb').write(data)
            dump(data)
        else:
            sys.exit(__doc__)
    except IndexError:
        sys.exit(__doc__)
    except LpError as e:
        sys.exit(f'[lp] 错误: {e}')
