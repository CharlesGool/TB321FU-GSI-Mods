#!/usr/bin/env python3
"""给 32 位 vendor 库按 file_contexts 算 SELinux 标签。

用法: label.py <lib 根目录> <file_contexts>...   (后面的文件可以多个,按给的顺序,后面的优先)
输出: 每个文件/目录一行 "<相对路径>\t<context>"。路径按 /vendor/lib/<相对路径> 匹配。
匹配规则近似 libselinux:正则整串匹配;多条命中时取固定前缀最长的,一样长取靠后的。
"""
import os, re, sys

def load(paths):
    specs = []
    for p in paths:
        for line in open(p, encoding='utf-8', errors='replace'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            f = line.split()
            if len(f) < 2:
                continue
            pat, ctx = f[0], f[-1]
            if len(f) == 3 and f[1] not in ('--', '-d', '-c', '-b', '-s', '-p', '-l'):
                continue
            ftype = f[1] if len(f) == 3 else None
            try:
                rx = re.compile('^' + pat + '$')
            except re.error:
                continue
            stem = re.split(r'[\\(\[\.\*\+\?\{\|]', pat, 1)[0]
            specs.append((rx, ctx, len(stem), ftype))
    return specs

def lookup(specs, path, isdir):
    best = None
    for i, (rx, ctx, stem, ft) in enumerate(specs):
        if ft == '-d' and not isdir: continue
        if ft == '--' and isdir: continue
        if ft in ('-c', '-b', '-s', '-p', '-l'): continue
        if rx.match(path):
            if best is None or stem >= best[0]:
                best = (stem, ctx)
    return best[1] if best else None

root = os.path.realpath(sys.argv[1])
specs = load(sys.argv[2:])
bad = 0
for dp, dn, fn in os.walk(root):
    for name in sorted(dn + fn):
        full = os.path.join(dp, name)
        rel = os.path.relpath(full, root)
        ctx = lookup(specs, '/vendor/lib/' + rel, os.path.isdir(full))
        if ctx is None:
            print('NOLABEL', rel, file=sys.stderr); bad += 1; continue
        print(rel + '\t' + ctx)
sys.exit(1 if bad else 0)
