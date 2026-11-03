#!/usr/bin/env python3
"""在电脑上做 custom-font/control 能装的字体包(zip)。

用法示例:
  # 西文无衬线(系统默认界面字体)换成一套静态字体
  toolkit/make-font-pack.py --name ubuntu --out ubuntu.zip \\
      --sans-regular Ubuntu-R.ttf --sans-bold Ubuntu-B.ttf --sans-italic Ubuntu-RI.ttf --sans-bolditalic Ubuntu-BI.ttf
  # 中文(简体)换成一个可变字体,再把 Google Sans 也换掉
  toolkit/make-font-pack.py --name wenkai --out wenkai.zip \\
      --cjk-variable LXGWWenKai-VF.ttf --google-sans LXGWWenKai-Regular.ttf
  # 设备上装:adb push wenkai.zip /data/local/tmp/ && heraldctl font install /data/local/tmp/wenkai.zip && heraldctl font use wenkai && 重启

包的内容(都在 zip 顶层):
  font_fallback.xml        从系统原版改出来:sans-serif 家族 / 中日韩无衬线字体换成你给的文件
  fonts_customization.xml  只有给了 --google-sans 才有:把 Google Sans 系列的文件名换成你给的字体
  Custom-*.ttf / .otf      你的字体文件(改名后放进来)
没改的系统字体不放进包,设备端装包时自动做成指向 /system/fonts 的符号链接。

选项:
  --sans-regular/--sans-bold/--sans-italic/--sans-bolditalic  静态字体(至少要 regular;缺的粗细/斜体由系统合成)
  --sans-variable   可变字体(wght 轴),和上面互斥
  --cjk-regular/--cjk-bold/--cjk-variable   中日韩无衬线字体(同样,可变和静态互斥);.ttc 不支持
  --cjk-lang        换哪些语言:默认 zh-Hans;写 all 则 zh-Hans / zh-Hant / ja / ko 的无衬线字体全换
  --google-sans     换掉 /product 里的 Google Sans(状态栏时钟、Pixel 启动器等用它)
  --stock-xml/--stock-oem   系统原版 font_fallback.xml / fonts_customization.xml,默认用 toolkit/fontpack/stock/ 里的(来自底包)
"""
import argparse
import os
import re
import shutil
import sys
import zipfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
MAGICS = (b'\x00\x01\x00\x00', b'OTTO', b'true', b'ttcf', b'wOFF')
MAX_MB = 200


def die(msg):
    sys.exit('错误: ' + msg)


def check_font(path, what):
    if not os.path.isfile(path):
        die('%s 不存在: %s' % (what, path))
    with open(path, 'rb') as f:
        head = f.read(4)
    if head not in MAGICS or head == b'wOFF':
        die('%s 不是 ttf/otf 字体(文件头 %r): %s' % (what, head, path))
    if head == b'ttcf':
        die('%s 是 .ttc 字体集合,暂不支持,请拆成单个 ttf/otf: %s' % (what, path))


def font_el(fname, weight=None, style=None, variable=False):
    e = ET.Element('font')
    if variable:
        e.set('supportedAxes', 'wght')
    else:
        e.set('weight', str(weight))
        e.set('style', style)
    e.text = fname
    return e


def pick_files(args, prefix, out_files):
    """按 --<prefix>-* 选项收集 [(包内文件名, 源路径)] 和 font 元素;返回 font 元素列表或 None(没给)。"""
    var = getattr(args, prefix + '_variable', None)
    reg = getattr(args, prefix + '_regular', None)
    bold = getattr(args, prefix + '_bold', None)
    ital = getattr(args, prefix + '_italic', None)
    bi = getattr(args, prefix + '_bolditalic', None)
    if var and (reg or bold or ital or bi):
        die('--%s-variable 和静态选项不能同时给' % prefix)
    if not (var or reg):
        if bold or ital or bi:
            die('给了 --%s-bold/italic 却没有 --%s-regular' % (prefix, prefix))
        return None
    els = []

    def add(src, label, **kw):
        check_font(src, '--%s-%s' % (prefix, label))
        ext = os.path.splitext(src)[1].lower()
        name = 'Custom-%s-%s%s' % (prefix, label, ext)
        out_files[name] = src
        els.append(font_el(name, **kw))

    if var:
        add(var, 'variable', variable=True)
    else:
        add(reg, 'regular', weight=400, style='normal')
        if bold:
            add(bold, 'bold', weight=700, style='normal')
        if ital:
            add(ital, 'italic', weight=400, style='italic')
        if bi:
            add(bi, 'bolditalic', weight=700, style='italic')
    return els


def build_fallback(stock_xml, sans, cjk, cjk_lang):
    tree = ET.parse(stock_xml)
    root = tree.getroot()
    notes = []
    if sans is not None:
        fams = [f for f in root.findall('family') if f.get('name') == 'sans-serif']
        if len(fams) != 1:
            die('原版 xml 里 sans-serif 家族不是恰好一个(%d 个)' % len(fams))
        for c in list(fams[0]):
            fams[0].remove(c)
        for e in sans:
            fams[0].append(e)
        notes.append('sans-serif 家族已换')
    if cjk is not None:
        wanted = None if cjk_lang == 'all' else {'zh-Hans'}
        n = 0
        for fam in root.findall('family'):
            lang = (fam.get('lang') or '')
            if not lang:
                continue
            langs = {x.strip() for x in lang.split(',')}
            if wanted is not None and not (langs & wanted):
                continue
            for f in list(fam.findall('font')):
                if f.get('fallbackFor'):
                    continue
                if 'NotoSansCJK-Regular.ttc' not in ''.join(f.itertext()):
                    continue
                idx = list(fam).index(f)
                fam.remove(f)
                for k, e in enumerate(cjk):
                    fam.insert(idx + k, ET.fromstring(ET.tostring(e)))
                n += 1
        if n == 0:
            die('原版 xml 里没找到要换的中日韩无衬线字体(lang=%s)' % cjk_lang)
        notes.append('中日韩无衬线字体换了 %d 处(%s)' % (n, cjk_lang))
    return ET.tostring(root, encoding='unicode'), notes


def build_oem(stock_oem, gs_name):
    text = open(stock_oem, encoding='utf-8').read()
    new, n = re.subn(r'GoogleSans[A-Za-z0-9-]*\.ttf', gs_name, text)
    if n == 0:
        die('原版 fonts_customization.xml 里没找到 GoogleSans 字体引用')
    return new, n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--name', required=True)
    ap.add_argument('--out', required=True)
    for p in ('sans', 'cjk'):
        for k in ('regular', 'bold', 'italic', 'bolditalic', 'variable'):
            ap.add_argument('--%s-%s' % (p, k))
    ap.add_argument('--cjk-lang', default='zh-Hans', choices=('zh-Hans', 'all'))
    ap.add_argument('--google-sans')
    ap.add_argument('--stock-xml', default=os.path.join(HERE, 'fontpack', 'stock', 'font_fallback.xml'))
    ap.add_argument('--stock-oem', default=os.path.join(HERE, 'fontpack', 'stock', 'fonts_customization.xml'))
    args = ap.parse_args()

    if not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', args.name) or args.name.startswith('.') or '..' in args.name:
        die('--name 只能是字母数字 . _ -(不超过 64,不以点开头,不含 ..)')
    files = {}
    sans = pick_files(args, 'sans', files)
    cjk = pick_files(args, 'cjk', files)
    if args.cjk_bold or args.cjk_regular or args.cjk_variable:
        pass
    if sans is None and cjk is None and not args.google_sans:
        die('至少要给 --sans-*、--cjk-* 或 --google-sans 之一')
    notes = []
    xml_text, n1 = build_fallback(args.stock_xml, sans, cjk, args.cjk_lang)
    notes += n1
    oem_text = None
    if args.google_sans:
        check_font(args.google_sans, '--google-sans')
        gs = 'Custom-google-sans' + os.path.splitext(args.google_sans)[1].lower()
        files[gs] = args.google_sans
        oem_text, n = build_oem(args.stock_oem, gs)
        notes.append('Google Sans 引用换了 %d 处' % n)
    total = sum(os.path.getsize(p) for p in files.values())
    if total > MAX_MB * 1024 * 1024:
        die('字体文件合计 %.1f MB,超过 %d MB 上限' % (total / 1048576, MAX_MB))
    with zipfile.ZipFile(args.out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('font_fallback.xml', '<?xml version="1.0" encoding="utf-8"?>\n' + xml_text + '\n')
        if oem_text is not None:
            z.writestr('fonts_customization.xml', oem_text)
        for name, src in sorted(files.items()):
            z.write(src, name)
    print('已生成 %s(包名建议 %s,字体 %d 个,%.1f MB)' % (args.out, args.name, len(files), total / 1048576))
    for n in notes:
        print('  - ' + n)
    print('设备上: adb push %s /data/local/tmp/ && heraldctl font install /data/local/tmp/%s %s && heraldctl font use %s,然后重启'
          % (os.path.basename(args.out), os.path.basename(args.out), args.name, args.name))


if __name__ == '__main__':
    main()
