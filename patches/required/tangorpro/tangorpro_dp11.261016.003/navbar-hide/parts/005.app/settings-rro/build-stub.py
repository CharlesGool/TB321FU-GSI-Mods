#!/usr/bin/env python3
"""为 Settings 的 RRO 生成"链接用桩包"的资源源码:包名 com.android.settings,把 overlay xml 里引用到的
Settings 资源 / 属性按真实 SettingsGoogle 的 ID 声明成 public。overlay 链接这个桩包(而不是真 APK)就能引用私有资源,
编出来的 ID 和真 Settings 一致。
用法: build-stub.py <SettingsGoogle.apk 的 `aapt2 dump resources` 输出> <apktool 解出的 res/values/attrs.xml> <overlay res 目录> <输出目录>"""
import os, re, sys
dump, attrs_xml, res_dir, out = sys.argv[1:5]
ids = {}
for l in open(dump, encoding='utf-8', errors='replace'):
    m = re.match(r'\s*resource (0x7f[0-9a-f]{6}) ([a-z]+)/([A-Za-z0-9_.]+)', l)
    if m:
        ids[(m.group(2), m.group(3))] = m.group(1)
import xml.etree.ElementTree as ET
attr_def = {}   # 属性名 -> 原样的 <attr …>(带 enum / flag 子项,枚举值才编得对)
for a in ET.parse(attrs_xml).getroot().iter('attr'):
    n = a.get('name')
    if n and n not in attr_def and (a.get('format') or len(a)):
        attr_def[n] = ET.tostring(a, encoding='unicode').strip()
need = set()
for root, _, files in os.walk(res_dir):
    for f in files:
        s = open(os.path.join(root, f), encoding='utf-8').read()
        for t, n in re.findall(r'@com\.android\.settings:([a-z]+)/([A-Za-z0-9_.]+)', s):
            need.add((t, n))
        for n in re.findall(r'\bsettings:([A-Za-z0-9_]+)=', s):
            need.add(('attr', n))
os.makedirs(f'{out}/res/values', exist_ok=True)
pub, vals = [], []
for t, n in sorted(need):
    i = ids.get((t, n))
    if not i:
        sys.exit(f'Settings 里没有 {t}/{n}')
    pub.append(f'    <public type="{t}" name="{n}" id="{i}"/>')
    if t == 'attr':
        vals.append('    ' + attr_def.get(n, f'<attr name="{n}" format="string"/>'))
    elif t == 'string':
        vals.append(f'    <string name="{n}">x</string>')
    elif t in ('raw', 'drawable'):
        vals.append(f'    <item type="{t}" name="{n}">@android:color/transparent</item>')
open(f'{out}/res/values/public.xml', 'w').write('<resources>\n' + '\n'.join(pub) + '\n</resources>\n')
open(f'{out}/res/values/values.xml', 'w').write('<resources>\n' + '\n'.join(vals) + '\n</resources>\n')
open(f'{out}/AndroidManifest.xml', 'w').write('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.android.settings"/>\n')
print(f'桩包:{len(need)} 个资源 / 属性')
