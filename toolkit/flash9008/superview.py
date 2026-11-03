"""按 rawprogram XML 把 9008 包里的 super 分片"虚拟地"拼回去,不落盘 13GB 的整块 super。

fh_loader 刷 super 时,就是把 XML 里 label="super" 的每一条 <program> 的文件,写到
start_sector × SECTOR_SIZE_IN_BYTES 的位置。第一条(start_sector 最小)就是 super 的开头,
文件是 super_1(lp 元数据)。这里按同样的规则建一张"super 内偏移 → 哪个文件的哪个偏移"的表,
再按 lp 元数据里每个逻辑分区的 extent 去读。没被任何 <program> 覆盖的地方当成 0
(和刷机后的真实内容不一定一样,所以 read() 碰到这种区域会报出来)。
"""
import os
import xml.etree.ElementTree as ET

import lp


class SuperError(Exception):
    pass


def super_programs(xml_path):
    """XML 里 label=super 的 program 条目,按 start_sector 排好。"""
    out = []
    for p in ET.parse(xml_path).getroot().iter('program'):
        if p.get('label') != 'super':
            continue
        out.append(dict(filename=p.get('filename'), start=int(p.get('start_sector')),
                        n=int(p.get('num_partition_sectors')), ss=int(p.get('SECTOR_SIZE_IN_BYTES')),
                        fso=int(p.get('file_sector_offset', '0'))))
    if not out:
        raise SuperError(f'{xml_path} 里没有 label="super" 的条目')
    out.sort(key=lambda e: e['start'])
    if len({e['ss'] for e in out}) != 1:
        raise SuperError('super 条目的 SECTOR_SIZE_IN_BYTES 不一致')
    return out


def find_file(fn, dirs, override=None):
    if override and fn in override:
        return override[fn]
    for d in dirs:
        p = os.path.join(d, fn)
        if os.path.exists(p):
            return p
    raise SuperError(f'找不到 {fn}(找过: {", ".join(dirs)})')


class SuperView:
    def __init__(self, xml_path, dirs, override=None):
        self.entries = super_programs(xml_path)
        self.ss = self.entries[0]['ss']
        self.start = self.entries[0]['start']
        for e in self.entries:
            if not e['filename']:
                raise SuperError(f'super 条目 start_sector={e["start"]} 的 filename 是空的')
            if e['fso']:
                raise SuperError(f'{e["filename"]}: file_sector_offset 不是 0,不支持')
            e['path'] = find_file(e['filename'], dirs, override)
            size = os.path.getsize(e['path'])
            if size != e['n'] * self.ss:
                raise SuperError(f'{e["filename"]}: 文件 {size} 字节,XML 写的是 {e["n"]} 扇区 × {self.ss} = {e["n"] * self.ss}')
            e['off'] = (e['start'] - self.start) * self.ss
            e['end'] = e['off'] + size
        for a, b in zip(self.entries, self.entries[1:]):
            if a['end'] > b['off']:
                raise SuperError(f'{a["filename"]} 和 {b["filename"]} 在 super 里重叠')
        with open(self.entries[0]['path'], 'rb') as f:
            head = bytearray(f.read())
        lp.verify(head, quiet=True)
        self.meta = head
        self.size = lp.super_size(head)
        self.parts = {}
        for name, exts in lp.partitions(head):
            if not exts:
                continue
            if len(exts) != 1:
                raise SuperError(f'{name} 有多个 extent,不支持')
            off, ln = exts[0]
            if off + ln > self.size:
                raise SuperError(f'{name} 超出 super 大小')
            self.parts[name] = (off, ln)
        rs = sorted((o, o + l, n) for n, (o, l) in self.parts.items())
        for (a1, b1, n1), (a2, b2, n2) in zip(rs, rs[1:]):
            if b1 > a2:
                raise SuperError(f'lp 元数据里 {n1} 和 {n2} 重叠')
        last = self.entries[-1]
        if last['end'] > self.size:
            raise SuperError(f'{last["filename"]} 写到了 super 末尾之外')

    def entry_at(self, off):
        for e in self.entries:
            if e['off'] == off:
                return e
        return None

    def read(self, off, ln, allow_gap=False):
        out = bytearray()
        pos, end = off, off + ln
        while pos < end:
            e = next((e for e in self.entries if e['off'] <= pos < e['end']), None)
            if e is None:
                nxt = min([x['off'] for x in self.entries if x['off'] > pos] + [end])
                if not allow_gap:
                    raise SuperError(f'super+{pos} 起没有任何文件覆盖(刷机后这里是原来盘上的内容,不确定)')
                out += b'\0' * (nxt - pos)
                pos = nxt
                continue
            take = min(end, e['end']) - pos
            with open(e['path'], 'rb') as f:
                f.seek(pos - e['off'])
                out += f.read(take)
            pos += take
        return bytes(out)

    def part_read(self, name, off, ln):
        po, pl = self.parts[name]
        if off < 0:
            off += pl
        if off + ln > pl:
            raise SuperError(f'读 {name} 越界')
        return self.read(po + off, ln)

    def owner(self, e):
        """这条 program 写进了哪个逻辑分区(写元数据区的返回 '(lp 元数据)')。"""
        if e['off'] == 0:
            return '(lp 元数据)'
        hits = [n for n, (o, l) in self.parts.items() if o <= e['off'] < o + l]
        if len(hits) != 1:
            raise SuperError(f'{e["filename"]} 的起点 super+{e["off"]} 不在任何逻辑分区里')
        o, l = self.parts[hits[0]]
        if e['end'] > o + l:
            raise SuperError(f'{e["filename"]} 超出了分区 {hits[0]} 的末尾({e["end"]} > {o + l})')
        return hits[0]
