#!/usr/bin/env python3
"""custom-font/hook:给反编译后的 framework.jar 插一处调用(幂等;找不到目标方法就失败退出)。

  SystemFonts.getSystemFontConfigInternal(String fontsXml, String systemFontDir, String oemXml, String productFontDir, Map, J, I)
  静态方法,开头把前四个路径参数各交给 FontCompatHelper 换一遍(有可用字体包就换成包里的路径,否则原样回来)。

插在方法的第一条指令前(跳过 .locals/.param/.annotation 这些声明)。p0..p3 对应 v12..v15(.locals 12),
都在 invoke-static 非 range 形式的 4 位寄存器范围内;这里校验一下,.locals 变了就失败退出,免得汇编出错。
用法: patch_framework.py <apktool 反编译目录>
输出: 一行 "OK <文件> <方法>",以及最后一行改过的 smali 相对路径(给 apply.sh 算要换哪份 dex)。
"""
import glob
import os
import sys

HOOK = 'Lcom/android/internal/os/FontCompatHelper;'
REL = 'android/graphics/fonts/SystemFonts.smali'
SIG = 'getSystemFontConfigInternal(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;JI)Landroid/text/FontConfig;'
CALL = '\n'.join(
    '    invoke-static {%s}, %s->%s(Ljava/lang/String;)Ljava/lang/String;\n    move-result-object %s' % (p, HOOK, fn, p)
    for p, fn in (('p0', 'xml'), ('p1', 'dir'), ('p2', 'oem'), ('p3', 'pdir')))


def main():
    root = sys.argv[1]
    hits = glob.glob(os.path.join(root, 'smali*', REL))
    if len(hits) != 1:
        sys.exit('FAIL 找不到(或不止一份)%s: %s' % (REL, hits))
    path = hits[0]
    lines = open(path, encoding='utf-8').read().split('\n')
    starts = [i for i, l in enumerate(lines) if l.startswith('.method ') and l.endswith(' ' + SIG)]
    if len(starts) != 1:
        sys.exit('FAIL %s 里方法 %s 命中 %d 处' % (path, SIG, len(starts)))
    if 'static' not in lines[starts[0]].split():
        sys.exit('FAIL %s 不是静态方法,p0 不是第一个参数,补丁假设不成立' % SIG)
    i = starts[0] + 1
    in_anno = False
    locals_n = None
    while i < len(lines):
        s = lines[i].strip()
        if s == '.end method':
            sys.exit('FAIL %s 没有指令' % SIG)
        if s.startswith('.locals'):
            locals_n = int(s.split()[1])
        if in_anno:
            if s == '.end annotation':
                in_anno = False
        elif s.startswith('.annotation'):
            in_anno = True
        elif s == '' or s.startswith(('.locals', '.registers', '.param', '.end param', '.prologue')):
            pass
        else:
            break
        i += 1
    if locals_n is None or locals_n + 3 > 15:
        sys.exit('FAIL .locals=%s,p3 的寄存器号超过 v15,要改成 invoke-static/range' % locals_n)
    done = HOOK not in '\n'.join(lines[starts[0]:i + 10])
    if done:
        lines.insert(i, CALL)
        lines.insert(i + 1, '')
        open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    print('OK %s getSystemFontConfigInternal%s' % (REL, '' if done else '(已有)'))
    print(os.path.relpath(path, root))


if __name__ == '__main__':
    main()
