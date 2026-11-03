#!/usr/bin/env python3
"""spoof/app-spoof:给反编译后的 framework.jar 插三处调用(幂等;找不到目标方法就失败退出)。

  ZygoteInit.main([String)V                                  开头  ZygoteCompatHelper.init()
  Instrumentation.newApplication(ClassLoader,String,Context)  开头  ZygoteCompatHelper.setProps(p3)
  Instrumentation.newApplication(Class,Context)  (static)     开头  ZygoteCompatHelper.setProps(p1)

插在方法的第一条指令前(跳过 .locals/.param/.annotation 这些声明),这时参数寄存器一定还是传进来的值。
用法: patch_framework.py <apktool 反编译目录>
输出: 每处一行 "OK <文件> <方法>",以及最后一行改过的 smali 相对路径(空格分隔,给 apply.sh 算要换哪份 dex)。
"""
import glob
import os
import re
import sys

HOOK = 'Lcom/android/internal/os/ZygoteCompatHelper;'
TARGETS = [
    ('com/android/internal/os/ZygoteInit.smali',
     '.method public static greylist main([Ljava/lang/String;)V',
     '    invoke-static {}, %s->init()V' % HOOK),
    ('android/app/Instrumentation.smali',
     'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;',
     '    invoke-static {p3}, %s->setProps(Landroid/content/Context;)V' % HOOK),
    ('android/app/Instrumentation.smali',
     'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;',
     '    invoke-static {p1}, %s->setProps(Landroid/content/Context;)V' % HOOK),
]


def find_smali(root, rel):
    hits = glob.glob(os.path.join(root, 'smali*', rel))
    if len(hits) != 1:
        sys.exit('FAIL 找不到(或不止一份)%s: %s' % (rel, hits))
    return hits[0]


def patch(path, sig, call):
    lines = open(path, encoding='utf-8').read().split('\n')
    if sig.startswith('.method'):
        starts = [i for i, l in enumerate(lines) if l == sig]
    else:
        starts = [i for i, l in enumerate(lines) if l.startswith('.method ') and l.endswith(' ' + sig)]
    if len(starts) != 1:
        sys.exit('FAIL %s 里方法 %s 命中 %d 处' % (path, sig, len(starts)))
    i = starts[0] + 1
    in_anno = False
    while i < len(lines):
        s = lines[i].strip()
        if s == '.end method':
            sys.exit('FAIL %s 的 %s 没有指令' % (path, sig))
        if in_anno:
            if s == '.end annotation':
                in_anno = False
        elif s.startswith('.annotation'):
            in_anno = True
        elif s == '' or s.startswith(('.locals', '.registers', '.param', '.end param', '.prologue')):
            pass
        else:
            break                     # 第一条 .line / .local / 指令
        i += 1
    # 幂等:已经插过就不再插
    window = '\n'.join(lines[starts[0]:i + 3])
    if HOOK in window:
        return False
    lines.insert(i, call)
    lines.insert(i + 1, '')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    return True


def main():
    root = sys.argv[1]
    changed = []
    for rel, sig, call in TARGETS:
        p = find_smali(root, rel)
        done = patch(p, sig, call)
        print('OK %s %s%s' % (rel, sig.split('(')[0].split(' ')[-1], '' if done else '(已有)'))
        r = os.path.relpath(p, root)
        if r not in changed:
            changed.append(r)
    print(' '.join(changed))


if __name__ == '__main__':
    main()
