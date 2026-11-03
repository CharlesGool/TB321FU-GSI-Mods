#!/usr/bin/env python3
# 在 CameraDeviceInfo.checkIds() 开头插入:back_wide / back_tele 也按系统实际的相机列表核对,不存在就置成 "-1"(INVALID_ID)。
# 原版 checkIds 核对了 back_main/aux1-3/bokeh/ir/optical 等,唯独漏了这两项;TB321FU 的配置里 back_wide=2,
# 系统没有 2 号相机时拍照模块照样去取它 → getCameraCharacteristics: unknown device 2 闪退。
# 用法: patch_checkids.py <apktool 解出的目录>(toolkit/lib/apk-smali.sh 会把它作为最后一个参数传进来)
import glob, re, sys
hits = glob.glob(sys.argv[1] + '/smali*/com/zui/camera/app/CameraDeviceInfo.smali')
if len(hits) != 1:
    sys.exit(f'CameraDeviceInfo.smali 找到 {len(hits)} 份(APK 版本变了?)')
p = hits[0]
s = open(p, encoding='utf-8').read()
C = 'Lcom/zui/camera/app/CameraDeviceInfo;'
if 'tb321fu_idcheck_' in s:
    sys.exit('已经打过补丁')
m = re.search(r'(\.method public checkIds\(\[Ljava/lang/String;\)V\n\s+\.locals (\d+)\n)', s)
if not m:
    sys.exit('找不到 checkIds([Ljava/lang/String;)V')
if int(m.group(2)) < 2:
    sys.exit('checkIds 的 .locals 小于 2,和预期的版本不同')
for f in ('mBackWideId', 'mBackTeleId'):
    if f'.field private {f}:Ljava/lang/String;' not in s:
        sys.exit(f'没有字段 {f}')
if f'.method public hasId(Ljava/lang/String;[Ljava/lang/String;)Z' not in s:
    sys.exit('没有 hasId(String, String[])')
block = '\n    # TB321FU-GSI: back_wide / back_tele 也按实际相机列表核对(原版漏了)\n    const-string v1, "-1"\n'
for f in ('mBackWideId', 'mBackTeleId'):
    lab = f'tb321fu_idcheck_{f}'
    block += f'''
    iget-object v0, p0, {C}->{f}:Ljava/lang/String;

    invoke-virtual {{p0, v0, p1}}, {C}->hasId(Ljava/lang/String;[Ljava/lang/String;)Z

    move-result v0

    if-nez v0, :{lab}

    iput-object v1, p0, {C}->{f}:Ljava/lang/String;

    :{lab}
'''
s = s[:m.end()] + block + s[m.end():]
open(p, 'w', encoding='utf-8').write(s)
print('checkIds 已补上 back_wide / back_tele 的核对')
