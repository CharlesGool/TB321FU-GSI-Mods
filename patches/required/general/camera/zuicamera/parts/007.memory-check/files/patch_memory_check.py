#!/usr/bin/env python3
# 联想相机拍照前 ImageCaptureManager.isMemoryFull() 判断"内存满了"就放弃拍照(日志 hasFullQueue true →
# "Not taking picture since Camera is closed or capture is not allowed")。原判断:
#     maxMemory() - totalMemory() <= 预估占用 + 50MB  → 满
# totalMemory() 是 ART 已向系统要到的堆容量,不是已用量;A17(DP11)上堆容量会长到上限(日志 max:512/512),
# 差值恒为 0,每次都判满。改成按真实已用量算:maxMemory() - (totalMemory() - freeMemory())。
# 用法: patch_memory_check.py <apktool 解出的目录>(toolkit/lib/apk-smali.sh 会把它作为最后一个参数传进来)
import glob, re, sys
root = sys.argv[1]
MARK = 'tb321fu_memory_check'
hits = glob.glob(root + '/smali*/com/zui/camera/capture/ImageCaptureManager.smali')
if len(hits) != 1:
    sys.exit(f'ImageCaptureManager.smali 找到 {len(hits)} 份(APK 版本变了?)')
p = hits[0]
s = open(p, encoding='utf-8').read()
if MARK in s:
    sys.exit('已经打过补丁')
m = re.search(r'\.method private isMemoryFull\(ILcom/zui/camera/util/Size;ZZ\)Z\n\s+\.locals (\d+)\n(.*?)\n\.end method', s, re.S)
if not m:
    sys.exit('找不到 isMemoryFull(ILcom/zui/camera/util/Size;ZZ)Z')
locals_n = int(m.group(1))
body = m.group(2)
# 判断用的那段:maxMemory → move-result-wide A;totalMemory → move-result-wide B;sub-long/2addr A, B
pat = re.compile(r'(invoke-virtual \{(\w+)\}, Ljava/lang/Runtime;->maxMemory\(\)J\n\s*\n\s*move-result-wide (\w+)\n\s*\n'
                 r'\s*invoke-virtual \{\2\}, Ljava/lang/Runtime;->totalMemory\(\)J\n\s*\n\s*move-result-wide (\w+)\n)'
                 r'(\s*\n\s*sub-long/2addr \3, \4\n)')
found = pat.findall(body)
if len(found) != 1:
    sys.exit(f'isMemoryFull 里 max-total 的判断找到 {len(found)} 处(预期 1 处),APK 版本变了?')
rt, a, b = found[0][1], found[0][2], found[0][3]
# 临时寄存器:B 是 vN 时用 v(N+2),v(N+3);要在 .locals 范围内且不和 A 重叠
nb = int(b[1:]) if b.startswith('v') else None
if nb is None or nb + 3 >= locals_n:
    sys.exit(f'寄存器 {b} 不在预期范围(.locals {locals_n})')
t = f'v{nb + 2}'
if a in (t, f'v{nb + 3}'):
    sys.exit('临时寄存器和已用寄存器冲突')
ins = (f'\n    # TB321FU-GSI {MARK}: totalMemory 是堆容量不是已用量,减去 freeMemory 得真实已用\n'
       f'    invoke-virtual {{{rt}}}, Ljava/lang/Runtime;->freeMemory()J\n\n'
       f'    move-result-wide {t}\n\n'
       f'    sub-long/2addr {b}, {t}\n')
body2 = pat.sub(lambda mm: mm.group(1) + ins + mm.group(5), body, count=1)
s = s[:m.start(2)] + body2 + s[m.end(2):]
open(p, 'w', encoding='utf-8').write(s)
print(f'isMemoryFull 改成 max - (total - free)(寄存器 {rt}/{a}/{b}/{t})')
