#!/usr/bin/env python3
"""把 bt.prop 应用到 product/etc/build.prop:已有的 key 就地改,没有的追加到末尾(带一行注释)。
用法: props.py <bt.prop> <build.prop>"""
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(dst, encoding="utf-8").read().splitlines()
added = []
for l in open(src, encoding="utf-8").read().splitlines():
    if not l.strip() or l.startswith("#"):
        continue
    k, v = l.split("=", 1)
    hit = False
    for i, x in enumerate(lines):
        if x.split("=", 1)[0] == k:
            lines[i] = f"{k}={v}"; hit = True
    if not hit:
        added.append(l)
if added:
    lines += ["", "# TB321FU: A2DP 走 vendor bluetooth_qti 软件编码, 关闭 LE Audio"] + added
open(dst, "w", encoding="utf-8").write("\n".join(lines) + "\n")
