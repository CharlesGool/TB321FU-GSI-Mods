#!/usr/bin/env python3
"""给 apktool 反编译出的 services.jar smali 打"流畅显示关 = N Hz"的钩子。

用法: apply_hook.py <反编译目录> [关闭时的 Hz,默认 120]

位置:DisplayModeDirector$SettingsObserver.updateRefreshRateSettingLocked(I)V 里,读完 min_refresh_rate / peak_refresh_rate、
调用 4 参数版 updateRefreshRateSettingLocked(FFFI)V 之前。设置里"流畅显示"关会写 peak_refresh_rate=60.0 且不碰 min,
所以 peak==60 且 min==0 就当成 N。别的值(包括 heraldctl refresh set 60,它同时写 min=60)原样不动。
幂等:已经有标记就跳过。必须正好命中一处,否则退出码 1(换底包后不能悄悄没打上)。
"""
import re
import struct
import sys
from pathlib import Path

MARK = "# herald-smooth-display"


def hex_float(hz):
    return "0x%08x" % struct.unpack(">I", struct.pack(">f", float(hz)))[0]


def main():
    root = Path(sys.argv[1])
    hz = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    files = [p for p in root.glob("smali*/com/android/server/display/mode/DisplayModeDirector$SettingsObserver.smali")]
    if len(files) != 1:
        print("FAIL: 找不到唯一的 DisplayModeDirector$SettingsObserver.smali(找到 %d 个)" % len(files))
        return 1
    p = files[0]
    s = p.read_text()
    if MARK in s:
        print("已有钩子,跳过 %s" % p.relative_to(root))
        return 0
    m = re.search(r"\.method public final updateRefreshRateSettingLocked\(I\)V.*?\.end method", s, re.S)
    if not m:
        print("FAIL: 找不到 updateRefreshRateSettingLocked(I)V")
        return 1
    body = m.group(0)
    anchor = re.compile(
        r"(?P<ind>[ \t]*)iget (?P<d>v\d+), p0, [^\n]*->mDefaultRefreshRate:F\n"
        r"\s*(?:\.line \d+\s*)?"
        r"invoke-virtual \{p0, (?P<min>v\d+), (?P<peak>v\d+), (?P=d), p1\}, "
        r"[^\n]*->updateRefreshRateSettingLocked\(FFFI\)V")
    hits = list(anchor.finditer(body))
    if len(hits) != 1:
        print("FAIL: 锚点命中 %d 处(预期 1):mDefaultRefreshRate → 4 参数 updateRefreshRateSettingLocked" % len(hits))
        return 1
    a = hits[0]
    ind, tmp, mn, pk = a.group("ind") or "    ", a.group("d"), a.group("min"), a.group("peak")
    code = (
        f"{ind}{MARK}:设置里\"流畅显示\"关 = peak 写 60 且 min 没设,当 {hz}Hz 用\n"
        f"{ind}const/high16 {tmp}, {hex_float(60)}    # 60.0f\n"
        f"{ind}cmpl-float {tmp}, {pk}, {tmp}\n"
        f"{ind}if-nez {tmp}, :herald_sd_skip\n"
        f"{ind}const/4 {tmp}, 0x0\n"
        f"{ind}cmpl-float {tmp}, {mn}, {tmp}\n"
        f"{ind}if-nez {tmp}, :herald_sd_skip\n"
        f"{ind}const/high16 {pk}, {hex_float(hz)}    # {float(hz)}f\n"
        f"{ind}:herald_sd_skip\n")
    new_body = body[:a.start()] + code + body[a.start():]
    p.write_text(s.replace(body, new_body))
    print("已打钩子:%s(关 = %dHz,常量 %s)" % (p.relative_to(root), hz, hex_float(hz)))
    return 0


sys.exit(main())
