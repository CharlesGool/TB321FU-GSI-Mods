#!/usr/bin/env python3
"""devopts-hide/hook:给反编译后的 framework.jar 插四处调用(幂等;找不到目标方法就失败退出)。

  ZygoteInit.main([String)V                                              开头  SettingsCompatHelper.init()
  Instrumentation.newApplication(ClassLoader,String,Context)             开头  SettingsCompatHelper.onApp(p3)
  Instrumentation.newApplication(Class,Context)  (static)                 开头  SettingsCompatHelper.onApp(p1)
  Settings$NameValueCache.getStringForUser(ContentResolver,String,I)      开头  有伪装值就直接 return

插在方法的第一条指令前(跳过 .locals/.param/.annotation 这些声明),这时参数寄存器一定还是传进来的值。
getStringForUser 的 .locals 很大(p2 对应的寄存器号超过 v15),所以用 invoke-static/range;
结果放 v0:方法一进来所有 v 寄存器都还没用,.locals >= 1 时 v0 可以随便占。
用法: patch_framework.py <apktool 反编译目录>
输出: 每处一行 "OK <文件> <方法>",以及最后一行改过的 smali 相对路径(空格分隔,给 apply.sh 算要换哪份 dex)。
"""
import glob
import os
import sys

HOOK = 'Lcom/android/internal/os/SettingsCompatHelper;'
GET_SIG = 'getStringForUser(Landroid/content/ContentResolver;Ljava/lang/String;I)Ljava/lang/String;'
GET_CALL = '\n'.join([
    '    invoke-static/range {p2 .. p2}, %s->over(Ljava/lang/String;)Ljava/lang/String;' % HOOK,
    '    move-result-object v0',
    '    if-eqz v0, :herald_sc_pass',
    '    return-object v0',
    '    :herald_sc_pass',
])
# (相对路径, 方法签名或整行 .method, 要插的文本)
TARGETS = [
    ('com/android/internal/os/ZygoteInit.smali',
     '.method public static greylist main([Ljava/lang/String;)V',
     '    invoke-static {}, %s->init()V' % HOOK),
    ('android/app/Instrumentation.smali',
     'newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;',
     '    invoke-static {p3}, %s->onApp(Landroid/content/Context;)V' % HOOK),
    ('android/app/Instrumentation.smali',
     'newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;',
     '    invoke-static {p1}, %s->onApp(Landroid/content/Context;)V' % HOOK),
    ('android/provider/Settings$NameValueCache.smali', GET_SIG, GET_CALL),
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
    locals_n = None
    while i < len(lines):
        s = lines[i].strip()
        if s == '.end method':
            sys.exit('FAIL %s 的 %s 没有指令' % (path, sig))
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
            break                     # 第一条 .line / .local / 指令
        i += 1
    if call.count('v0') and (locals_n is None or locals_n < 1):
        sys.exit('FAIL %s 的 %s 没有 .locals >= 1,v0 不能占用' % (path, sig))
    # 幂等:已经插过就不再插
    window = '\n'.join(lines[starts[0]:i + 3 + call.count('\n')])
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
