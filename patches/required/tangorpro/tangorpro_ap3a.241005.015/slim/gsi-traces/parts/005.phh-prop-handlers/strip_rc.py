#!/usr/bin/env python3
"""从 vndk.rc 里删掉 phh 的属性处理段落。

  strip_rc.py <vndk.rc>

按 init rc 的段落(以 `on ` / `service ` / `import ` 开头的行起头,到下一个这样的行为止)处理。
删掉头部提到 `persist.sys.phh.` / `sys.phh.` / `persist.bluetooth.system_audio_hal.enabled` 的 `on property:...` 段落,
其余段落(post-fs、early-boot、phh_on_boot、boot_completed、ro.sf.lcd_density 重启 surfaceflinger、watchdogd-gsi…)原样保留。
一个都没匹配到就返回 3(调用方当"这个底包没有这些段落"处理)。
"""
import re
import sys

HEAD = re.compile(r"^(on|service|import)\s")
DROP = re.compile(r"^on\s.*(persist\.sys\.phh\.|sys\.phh\.|persist\.bluetooth\.system_audio_hal\.enabled)")

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
blocks, cur = [], []
for l in lines:
    if HEAD.match(l) and cur:
        blocks.append(cur); cur = []
    cur.append(l)
if cur:
    blocks.append(cur)
kept, dropped = [], []
for b in blocks:
    (dropped if DROP.match(b[0]) else kept).append(b)
if not dropped:
    sys.exit(3)
out = "".join("".join(b) for b in kept)
if not out.endswith("\n"):
    out += "\n"
open(path, "w", encoding="utf-8").write(out)
for b in dropped:
    print("  - " + b[0].strip())
print(f"  删 {len(dropped)} 段,留 {len(kept)} 段")
