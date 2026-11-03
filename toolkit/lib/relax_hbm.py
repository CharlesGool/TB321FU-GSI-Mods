#!/usr/bin/env python3
"""stdin: 原厂 display_id_*.xml;stdout: 放宽 <highBrightnessMode> 限制后的版本。
参数 lux(默认的 display-config 用):
- <minimumLux>  → 0       (不再要求环境光 ≥ 10000 lux 才放行 HBM;时间限制保留原厂)
参数 full(hbm-unlimited 用):在 lux 的基础上
- <timing>      → 窗口内允许时长 = 窗口(不限时),最少剩余 1 秒
其余(亮度→尼特表、transitionPoint、HDR 比例表、升降速)原样不动。"""
import re, sys
mode = sys.argv[1] if len(sys.argv) > 1 else 'full'
if mode not in ('lux', 'full'): sys.exit('参数只能是 lux 或 full')
s = sys.stdin.read()
n0 = len(s)
def sub(tag, val, s):
    pat = re.compile(r'(<%s>)\s*[^<]*\s*(</%s>)' % (tag, tag))
    if not pat.search(s):
        sys.exit('原厂 xml 里没有 <%s>,格式和预期不同' % tag)
    return pat.sub(lambda m: m.group(1) + val + m.group(2), s, count=1)
if '<highBrightnessMode' not in s:
    sys.exit('原厂 xml 里没有 <highBrightnessMode>')
s = sub('minimumLux', '0', s)
if mode == 'lux':
    sys.stdout.write(s); sys.exit(0)
win = re.search(r'<timeWindowSecs>\s*(\d+)', s)
if not win: sys.exit('原厂 xml 里没有 <timeWindowSecs>')
s = sub('timeMaxSecs', win.group(1), s)
s = sub('timeMinSecs', '1', s)
sys.stdout.write(s)
