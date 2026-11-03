#!/usr/bin/env python3
# 联想相机里依赖本系统没有的组件的功能:从 TB321FU 的配置里去掉,或让它点了不崩。
# 1. raw/app_features(资源名被混淆,按内容找):TB321FU 条目的模式栏 modules-id 去掉
#    29 = 互联录制(InterConnectRecord,要联想互联服务 com.zui.wifip2p)、6 = 微距(要 2 号相机,本系统没有),
#    并去掉 INTERCONNECT_RECORD 这条 feature。
# 2. DialogHelper.jumpToLenovoLegalInfo:直接 startActivity 联想隐私/许可页面(com.lenovo.lenovoprivacy,本系统没有),
#    没有 try → 点"许可协议/隐私政策"链接就崩。包一层 try/catch,找不到页面就什么都不做。
# 3. 设置页里的"水印"和"OCR"选项:不再显示。水印要相机 HAL 认出联想相机才生效(zuicamera 不再强行设 HAL 客户端属性,
#    免得影响别的相机应用),OCR 本系统跑不起来。设置页 CameraSettingsFragment.filterFrontBackCameraSetting 里本来就有
#    "满足条件就 recursiveDelete 这个选项"的分支,这里把两处的条件去掉,改成一律删除。
# 用法: patch_hide.py <apktool 解出的目录>
import glob, os, re, sys
dec = sys.argv[1]
DROP = {'29', '6'}
if os.environ.get('HIDE_KEEP_MACRO') == '1':   # macro-camera-fix 开着:HAL 会报 2 号相机,微距保留
    DROP.discard('6')

# ---- 1. app_features ----
hits = [f for f in glob.glob(dec + '/res/*.json') if '"modules-id"' in open(f, encoding='utf-8', errors='replace').read()]
if len(hits) != 1:
    sys.exit(f'app_features 找到 {len(hits)} 份(APK 版本变了?)')
p = hits[0]; t = open(p, encoding='utf-8').read()
i = t.find('"device": "TB321FU,kirby_prc"')
if i < 0:
    sys.exit('app_features 里没有 TB321FU 条目')
j = t.find('"device"', i + 10); j = len(t) if j < 0 else j
blk = t[i:j]
m = re.search(r'"modules-id": "([0-9,]+)"', blk)
if not m:
    sys.exit('TB321FU 条目没有 modules-id')
ids = m.group(1).split(',')
keep = [x for x in ids if x not in DROP]
if keep == ids:
    sys.exit(f'modules-id 里没有要去掉的模式:{m.group(1)}')
blk2 = blk.replace(m.group(0), '"modules-id": "%s"' % ','.join(keep), 1)
blk2 = re.sub(r'\n[ \t]*\{"feature": "INTERCONNECT_RECORD"\},', '', blk2, count=1)
# V82:OCR 按钮(OCR_AILENS)点了就闪退:非 ROW 区域(本系统没有 ro.config.zui.region)时显示,走应用自带的联想 OCR 算法
#   (lcaf/Dolphin),本系统跑不起来。去掉这条 feature,按钮就不显示。
n_ocr = len(re.findall(r'\n[ \t]*\{"feature": "OCR(_AILENS)?"\},?', blk2))
blk2 = re.sub(r'\n[ \t]*\{"feature": "OCR(_AILENS)?"\},', '', blk2)
blk2 = re.sub(r',(\n[ \t]*)\{"feature": "OCR(_AILENS)?"\}(\s*\])', r'\3', blk2)
if n_ocr == 0 or re.search(r'"feature": "OCR(_AILENS)?"', blk2):
    sys.exit('TB321FU 条目里的 OCR_AILENS 没去掉(APK 版本变了?)')
t = t[:i] + blk2 + t[j:]
open(p, 'w', encoding='utf-8').write(t)
print(f'app_features: TB321FU 模式栏 {m.group(1)} -> {",".join(keep)},去掉 INTERCONNECT_RECORD、OCR_AILENS')

# ---- 2. jumpToLenovoLegalInfo ----
hits = glob.glob(dec + '/smali*/com/zui/camera/ui/DialogHelper.smali')
if len(hits) != 1:
    sys.exit(f'DialogHelper.smali 找到 {len(hits)} 份')
p = hits[0]; s = open(p, encoding='utf-8').read()
call = '    invoke-virtual {p1, p2}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V\n\n    return-void\n.end method'
k = s.find('.method public jumpToLenovoLegalInfo(')
e = s.find('.end method', k)
if k < 0 or s.find(call, k) != e - len(call) + len('.end method'):
    sys.exit('jumpToLenovoLegalInfo 和预期的不一样')
new = ('    :tb321fu_legal_try_start\n'
       '    invoke-virtual {p1, p2}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V\n'
       '    :tb321fu_legal_try_end\n'
       '    .catch Ljava/lang/Exception; {:tb321fu_legal_try_start .. :tb321fu_legal_try_end} :tb321fu_legal_catch\n\n'
       '    return-void\n\n'
       '    # TB321FU-GSI:本系统没有联想隐私/许可页面(com.lenovo.lenovoprivacy),找不到就忽略\n'
       '    :tb321fu_legal_catch\n'
       '    return-void\n.end method')
s = s[:e - len(call) + len('.end method')] + new + s[e + len('.end method'):]
open(p, 'w', encoding='utf-8').write(s)
print('DialogHelper.jumpToLenovoLegalInfo:找不到页面时不再崩')

# ---- 3. 设置页去掉 水印 / OCR ----
hits = glob.glob(dec + '/smali*/com/zui/camera/settings/CameraSettingsActivity$CameraSettingsFragment.smali')
if len(hits) != 1:
    sys.exit(f'CameraSettingsFragment.smali 找到 {len(hits)} 份')
p = hits[0]; s = open(p, encoding='utf-8').read()
# OCR:isAilensEnabled 或 isRow 才删 → 一律删(去掉 isRow 后面那条跳过删除的 if-eqz)
ocr = re.compile(r'(ApiHelper;->isRow\(\)Z\n\n    move-result v9\n\n)    if-eqz v9, :cond_\w+\n\n(    :cond_\w+\n    const-string v9, "pref_camera_ocr")')
# 水印:AOSP_MODE 不支持时跳过删除 → 一律删(去掉 AOSP_MODE 判断后那条 if-eqz)
wm = re.compile(r'(Feature;->AOSP_MODE:Lcom/zui/camera/app/AppFeatures\$Feature;\n\n    \.line \d+\n    invoke-static \{v9\}, Lcom/zui/camera/app/AppFeatures;->supported\(Lcom/zui/camera/app/AppFeatures\$Feature;\)Z\n\n    move-result v9\n\n)    if-eqz v9, :cond_\w+\n\n(    :cond_\w+\n    const-string v9, "pref_camera_watermark")')
for name, rx in (('OCR', ocr), ('水印', wm)):
    s, n = rx.subn(r'\1\2', s)
    if n != 1:
        sys.exit(f'设置页的{name}选项找到 {n} 处删除条件(APK 版本变了?)')
open(p, 'w', encoding='utf-8').write(s)
print('设置页:去掉 水印、OCR 选项')
