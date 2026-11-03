#!/usr/bin/env python3
# 扫原厂 vendor 的 init rc:找"带 reboot_on_failure/critical、跑的是 32 位程序(或 *32 但文件不存在)"的服务。
# 声明了 32 位 ABI 之后这类服务可能被触发,起不来就整机重启(V68 卡第一屏)。
# 用法: check_vendor32.py <vendor 挂载点> <已处理的服务名>...
# 输出: 每个没处理的危险服务一行 "名字<TAB>路径<TAB>原因";有输出时退出码 1。
import os, sys

root, handled = sys.argv[1], set(sys.argv[2:])

def resolve(path):
    # 镜像里的 /vendor/xxx → <root>/xxx;绝对符号链接也映射回镜像里
    for _ in range(8):
        if not path.startswith('/vendor/'):
            return None
        p = os.path.join(root, path[len('/vendor/'):])
        if not os.path.islink(p):
            return p
        t = os.readlink(p)
        path = t if t.startswith('/') else os.path.normpath(os.path.join(os.path.dirname(path), t))
    return None

def why(path):
    p = resolve(path)
    if p is None:
        return None                     # 不在 vendor 里(system/apex),不归这里管
    if not os.path.exists(p):
        return '文件不存在' if os.path.basename(path).endswith('32') else None
    with open(p, 'rb') as f:
        h = f.read(5)
    return '32 位 ELF' if h[:4] == b'\x7fELF' and h[4] == 1 else None

bad = []
for d, _, files in os.walk(os.path.join(root, 'etc/init')):
    for fn in sorted(files):
        if not fn.endswith('.rc'):
            continue
        svc = None
        for line in open(os.path.join(d, fn), errors='replace'):
            w = line.split('#', 1)[0].split()
            if not w:
                continue
            if w[0] in ('service', 'on', 'import'):
                if svc and svc['risky']:
                    bad.append(svc)
                svc = {'name': w[1], 'path': w[2], 'risky': False} if w[0] == 'service' and len(w) > 2 else None
            elif svc and w[0] in ('reboot_on_failure', 'critical'):
                svc['risky'] = True
        if svc and svc['risky']:
            bad.append(svc)

rc = 0
for s in bad:
    r = why(s['path'])
    if r and s['name'] not in handled:
        print(f"{s['name']}\t{s['path']}\t{r}")
        rc = 1
sys.exit(rc)
