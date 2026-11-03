#!/usr/bin/env python3
"""statusbar-netspeed/display:给反编译后的 framework.jar 插一处调用(幂等;找不到目标方法就失败退出)。

  Instrumentation.callApplicationOnCreate(Application)V   开头  HeraldNetSpeed.onApplicationCreate(p1)

插在方法的第一条指令前(跳过 .locals/.param/.annotation 这些声明),这时参数寄存器一定还是传进来的值。
每个 App 进程创建 Application 时都会走这里;HeraldNetSpeed 里第一件事就是比包名,不是 SystemUI 立刻返回。
用法: patch_framework.py <apktool 反编译目录>
输出: 一行 "OK <文件> <方法>",以及最后一行改过的 smali 相对路径(空格分隔,给 apply.sh 算要换哪份 dex)。
"""
import glob
import os
import sys

HOOK = 'Lcom/android/internal/util/HeraldNetSpeed;'
REL = 'android/app/Instrumentation.smali'
SIG = 'callApplicationOnCreate(Landroid/app/Application;)V'
CALL = '    invoke-static {p1}, %s->onApplicationCreate(Landroid/app/Application;)V' % HOOK


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
    if 'static' in lines[starts[0]].split():
        sys.exit('FAIL %s 是静态方法,p1 不是 app 参数,补丁假设不成立' % SIG)
    i = starts[0] + 1
    in_anno = False
    while i < len(lines):
        s = lines[i].strip()
        if s == '.end method':
            sys.exit('FAIL %s 的 %s 没有指令' % (path, SIG))
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
    done = HOOK not in '\n'.join(lines[starts[0]:i + 3])
    if done:
        lines.insert(i, CALL)
        lines.insert(i + 1, '')
        open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    print('OK %s callApplicationOnCreate%s' % (REL, '' if done else '(已有)'))
    print(os.path.relpath(path, root))


if __name__ == '__main__':
    main()
