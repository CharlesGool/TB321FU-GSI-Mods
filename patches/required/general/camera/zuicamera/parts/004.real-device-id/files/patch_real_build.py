#!/usr/bin/env python3
# 让联想相机看到真实机型,不受全局伪装影响。
# 全局伪装(spoof/global-pif)在开机早期用 resetprop 把 ro.product.{brand,device,manufacturer,model,name} 改成目标机型,
# 所以 android.os.Build.DEVICE 等变成 tangorpro。相机按 Build.DEVICE 选相机配置、判断机型分支,匹配不到就崩。
# 做法:加一个类 Lcom/zui/camera/TbRealBuild;,从不会被伪装的属性读真实值(ro.product.vendor.* → ro.product.system.*,
# 都读不到才回落到 Build.*);把应用自己代码(com/zui/camera/)里所有 sget-object Landroid/os/Build;->FIELD 换成调用它。
# 用法: patch_real_build.py <apktool 解出的目录>
import glob, os, re, sys
dec = sys.argv[1]
CLS = 'Lcom/zui/camera/TbRealBuild;'
HELPER = 'Lcom/zui/camera/developer/common/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
# Build 字段 → (方法名, 属性后缀)
FIELDS = {'DEVICE': ('device', 'device'), 'MODEL': ('model', 'model'), 'BRAND': ('brand', 'brand'),
          'MANUFACTURER': ('manufacturer', 'manufacturer'), 'PRODUCT': ('product', 'name')}

if not glob.glob(dec + '/smali*/com/zui/camera/developer/common/SystemProperties.smali'):
    sys.exit('应用里没有 com.zui.camera.developer.common.SystemProperties(APK 版本变了?)')
if glob.glob(dec + '/smali*/com/zui/camera/TbRealBuild.smali'):
    sys.exit('已经打过补丁')

pat = re.compile(r'^(\s*)sget-object (v\d+|p\d+), Landroid/os/Build;->(' + '|'.join(FIELDS) + r'):Ljava/lang/String;$', re.M)
total = 0; files = 0
for f in glob.glob(dec + '/smali*/com/zui/camera/**/*.smali', recursive=True):
    s = open(f, encoding='utf-8').read()
    n = 0
    def rep(m):
        global n
        n += 1
        ind, reg, fld = m.group(1), m.group(2), m.group(3)
        return f'{ind}invoke-static {{}}, {CLS}->{FIELDS[fld][0]}()Ljava/lang/String;\n\n{ind}move-result-object {reg}'
    s2 = pat.sub(rep, s)
    if n:
        open(f, 'w', encoding='utf-8').write(s2); total += n; files += 1
if total == 0:
    sys.exit('一处 Build.DEVICE/MODEL/... 都没找到(APK 版本变了?)')

methods = []
for fld, (name, suffix) in FIELDS.items():
    methods.append(f'''
.method public static {name}()Ljava/lang/String;
    .locals 3
    const-string v0, "ro.product.vendor.{suffix}"
    const-string v1, "ro.product.system.{suffix}"
    sget-object v2, Landroid/os/Build;->{fld}:Ljava/lang/String;
    invoke-static {{v0, v1, v2}}, {CLS}->pick(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    return-object v0
.end method
''')
smali = f'''.class public final {CLS}
.super Ljava/lang/Object;
.source "TbRealBuild.java"

# TB321FU-GSI 加的:真实机型(不受全局伪装影响)。见 patches/required/general/camera/zuicamera/parts/004.real-device-id/README.md

.method private constructor <init>()V
    .locals 0
    invoke-direct {{p0}}, Ljava/lang/Object;-><init>()V
    return-void
.end method

# 依次读 p0、p1 两个属性,第一个非空的就是结果;都空就用 p2(Build.* 的值)
.method private static pick(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
    .locals 2
    const-string v0, ""
    invoke-static {{p0, v0}}, {HELPER}
    move-result-object v1
    if-eqz v1, :second
    invoke-virtual {{v1}}, Ljava/lang/String;->isEmpty()Z
    move-result v0
    if-nez v0, :second
    return-object v1
    :second
    const-string v0, ""
    invoke-static {{p1, v0}}, {HELPER}
    move-result-object v1
    if-eqz v1, :fallback
    invoke-virtual {{v1}}, Ljava/lang/String;->isEmpty()Z
    move-result v0
    if-nez v0, :fallback
    return-object v1
    :fallback
    return-object p2
.end method
''' + ''.join(methods)
os.makedirs(dec + '/smali/com/zui/camera', exist_ok=True)
open(dec + '/smali/com/zui/camera/TbRealBuild.smali', 'w', encoding='utf-8').write(smali)
print(f'Build.DEVICE/MODEL/BRAND/MANUFACTURER/PRODUCT:{files} 个类共 {total} 处改成读真实机型')
