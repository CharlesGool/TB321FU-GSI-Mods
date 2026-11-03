#!/usr/bin/env python3
"""以一份已验证保数据的 rawprogram XML 为基准,生成新版本的 LUN0 刷机 XML。

用法:
  mk_rawprogram.py --base <基准 XML> --super1 <新 super_1.img> --system <新 system.img>
                   --super1-name super_1_vN.img --system-name super_4_vN.img --out <输出 XML>
                   [--check-xml rawprogram1.xml ...]

只改两行:
  - super 的第一条(lp 元数据那片):filename 换成 --super1-name
  - 写 system_a 的那条:filename 换成 --system-name,num_partition_sectors 换成 system 镜像的扇区数
    (哪一条是 system_a,按新 super_1 的 lp 元数据里 system_a 的起点算,不按文件名猜)
其余字节一个不动(按行原样拷贝,行尾也不变)。

生成后自动检查,任何一条不过就删掉输出并失败:
  1. 基准本身是保数据的(见 PROTECTED),不是就拒绝拿它当基准(V51 就是用错了基准清了数据)
  2. 输出和基准逐行比,只有上面两行不同,且这两行里只有那两个/三个属性不同;打印全文 diff
  3. 输出同样满足保数据
  4. 两个新文件的大小和 XML 里的扇区数对得上;system 那条的扇区数 × 扇区大小 = lp 里 system_a 的大小
  --check-xml 给的其它 LUN 的 XML(rawprogram1..5)也做保数据检查(只查,不改)
"""
import argparse
import difflib
import os
import re
import sys

sys.dont_write_bytecode = True  # 不在仓库里留 __pycache__
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lp  # noqa: E402

# 这些分区刷机时必须 filename="" 且不能有 <erase>:声明了分区但不写数据 = 原样保留。
#   userdata  用户数据本身
#   metadata  FBE 加密密钥的包装状态。只保 userdata 不保它,开机解不开 data,会被要求清 data(V48 第一版踩过)
#   persist   传感器校准、DRM、Wi-Fi/BT MAC 等出厂数据
# 必须出现在 LUN0 的 XML 里:
REQUIRED = ('userdata', 'metadata', 'persist')
# 出现了就必须 filename="":
PROTECTED = REQUIRED + ('misc', 'keystore', 'frp', 'proinfo', 'modemst1', 'modemst2', 'fsg', 'fsc', 'devinfo')


def die(msg):
    sys.exit(f'[rawprogram] 错误: {msg}')


def log(msg):
    print(f'[rawprogram] {msg}')


def protect_problems(path, required=REQUIRED):
    root = ET.parse(path).getroot()
    bad, seen = [], set()
    for el in root:
        lab = el.get('label')
        if lab not in PROTECTED:
            continue
        seen.add(lab)
        if el.tag == 'erase':
            bad.append(f'{lab}: 有 <erase>(会被擦除)')
        elif el.tag == 'program' and (el.get('filename') or '') != '':
            bad.append(f'{lab} @ {el.get("start_sector")}: filename="{el.get("filename")}"(会被覆盖)')
    for r in required:
        if r not in seen:
            bad.append(f'{r}: XML 里没有这个分区的条目(没法确认它被保留)')
    return bad


def attrs(line):
    return dict(re.findall(r'(\w+)="([^"]*)"', line))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--base', required=True)
    ap.add_argument('--super1', required=True)
    ap.add_argument('--system', required=True)
    ap.add_argument('--super1-name', required=True)
    ap.add_argument('--system-name', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--check-xml', nargs='*', default=[])
    ap.add_argument('--allow-wipe', action='store_true', help='基准是原厂"清数据"的 XML 时用:不做保数据检查,其余检查照做(只用来出清数据版)')
    a = ap.parse_args()

    bad = [] if a.allow_wipe else protect_problems(a.base)
    if bad:
        die('基准 XML 不是保数据的,不能当基准:\n  ' + '\n  '.join(bad))
    for x in a.check_xml:
        b = protect_problems(x, required=())
        if b:
            die(f'{x} 会动受保护分区:\n  ' + '\n  '.join(b))

    # 定位两条要改的 super 条目
    sup = sorted((p for p in ET.parse(a.base).getroot().iter('program') if p.get('label') == 'super'),
                 key=lambda p: int(p.get('start_sector')))
    if not sup:
        die('基准 XML 里没有 super 条目')
    ss = int(sup[0].get('SECTOR_SIZE_IN_BYTES'))
    super_start = int(sup[0].get('start_sector'))
    meta = bytearray(open(a.super1, 'rb').read())
    lp.verify(meta, quiet=True)
    parts = dict(lp.partitions(meta))
    if 'system_a' not in parts or len(parts['system_a']) != 1:
        die('新 super_1 里 system_a 不是单 extent')
    sys_off, sys_len = parts['system_a'][0]
    sys_size = os.path.getsize(a.system)
    if sys_size != sys_len:
        die(f'新 super_1 里 system_a 是 {sys_len} 字节,system 镜像是 {sys_size} 字节,对不上')
    if sys_off % ss or sys_size % ss:
        die(f'system_a 起点/大小不是 {ss} 的倍数')
    if len(meta) != int(sup[0].get('num_partition_sectors')) * ss:
        die(f'新 super_1 {len(meta)} 字节,基准 XML 第一条 super 是 {sup[0].get("num_partition_sectors")} 扇区')
    sys_sector = super_start + sys_off // ss
    targets = {str(super_start): dict(filename=a.super1_name),
               str(sys_sector): dict(filename=a.system_name, num_partition_sectors=str(sys_size // ss))}
    if str(sys_sector) not in {p.get('start_sector') for p in sup}:
        die(f'基准 XML 里没有 start_sector={sys_sector} 的 super 条目(system_a 的起点),super 布局和基准不一样')

    with open(a.base, 'rb') as f:
        lines = f.read().decode('utf-8').splitlines(keepends=True)
    out, hit = list(lines), {}
    for i, ln in enumerate(lines):
        if '<program' not in ln or 'label="super"' not in ln:
            continue
        st = attrs(ln).get('start_sector')
        if st not in targets:
            continue
        if st in hit:
            die(f'start_sector={st} 的 super 条目不止一行')
        new = ln
        for k, v in targets[st].items():
            new, n = re.subn(rf'(\s{k}=")[^"]*(")', rf'\g<1>{v}\g<2>', new)
            if n != 1:
                die(f'第 {i + 1} 行里 {k}= 出现了 {n} 次')
        out[i], hit[st] = new, i
    if set(hit) != set(targets):
        die('要改的两行没找全')
    tmp = a.out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(''.join(out).encode('utf-8'))

    # ---- 检查 ----
    problems = []
    with open(tmp, 'rb') as f:
        chk = f.read().decode('utf-8').splitlines(keepends=True)
    if len(chk) != len(lines):
        problems.append('行数变了')
    changed = [i for i, (x, y) in enumerate(zip(lines, chk)) if x != y]
    if not set(changed) <= set(hit.values()):
        problems.append(f'意外改动的行: {[i + 1 for i in changed if i not in hit.values()]}')
    for st, i in hit.items():
        ax, ay = attrs(lines[i]), attrs(chk[i])
        diffkeys = {k for k in set(ax) | set(ay) if ax.get(k) != ay.get(k)}
        if not diffkeys <= set(targets[st]):
            problems.append(f'第 {i + 1} 行改了不该改的属性 {sorted(diffkeys - set(targets[st]))}')
        if re.sub(r'"[^"]*"', '""', lines[i]) != re.sub(r'"[^"]*"', '""', chk[i]):
            problems.append(f'第 {i + 1} 行的结构变了')
    if not a.allow_wipe:
        problems += protect_problems(tmp)
    if problems:
        os.remove(tmp)
        die('生成的 XML 检查不过:\n  ' + '\n  '.join(problems))
    os.replace(tmp, a.out)
    print(''.join(difflib.unified_diff(lines, chk, a.base, a.out, n=0)), end='')
    log(f'和基准只差 {len(changed)} 行(super_1 + system_a)' + ('(清数据版,没做保数据检查)' if a.allow_wipe else f',受保护分区 {", ".join(REQUIRED)} 等 filename 均为空'))
    log(f'写出 {a.out}')


if __name__ == '__main__':
    try:
        main()
    except lp.LpError as e:
        die(str(e))
