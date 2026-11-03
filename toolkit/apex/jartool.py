#!/usr/bin/env python3
"""给"反编译 → 打 smali 补丁 → 回编"流程用的两个小工具(APEX 里的 javalib jar、framework jar 都适用)。

  swap-dex <原jar> <apktool回编出的jar> <输出jar>
      只把原 jar 里的 classes*.dex 换成回编出的 dex,其余条目(资源、.uau、MANIFEST)、顺序、
      时间戳、压缩方式都照原 jar。dex 保持不压缩,最后 zipalign 4。
      apktool 回编出的 jar 会丢 MANIFEST、改时间戳,不直接用它。

  smali-equiv <打完补丁的smali目录> <回编后再反编译的smali目录> <相对路径>...
      逐个比较 smali 文件。baksmali 反编译时会按地址重新给标签编号(:cond_0、:goto_1…),
      补丁里自定义的标签名(:herald_xxx)也会被改掉,所以比较前把所有标签统一成 :L,
      再去掉空行。剩下的指令、.line、.catch 都必须一模一样,否则说明回编结果和补丁不符。
"""
import os
import re
import subprocess
import sys
import zipfile

DEX = re.compile(r'^classes\d*\.dex$')
LABEL = re.compile(r'(?<=[\s{]):[A-Za-z_][A-Za-z0-9_]*\b')   # 标签只出现在空白或 { 后面;字段类型 ->x:L... 前面是字母


def die(msg):
    print(f'jartool: 错误: {msg}', file=sys.stderr)
    sys.exit(1)


def swap_dex(orig, built, out):
    with zipfile.ZipFile(orig) as zo, zipfile.ZipFile(built) as zb:
        od = sorted(n for n in zo.namelist() if DEX.match(n))
        bd = sorted(n for n in zb.namelist() if DEX.match(n))
        if not od:
            die(f'{orig} 里没有 classes*.dex')
        if od != bd:
            die(f'dex 个数对不上:原 jar {od},回编 {bd}')
        new = {n: zb.read(n) for n in bd}
        for n, d in new.items():
            if not d.startswith(b'dex\n') or len(d) < 0x70:
                die(f'回编出的 {n} 不是有效的 dex')
        tmp = out + '.unaligned'
        with zipfile.ZipFile(tmp, 'w') as zw:
            for i in zo.infolist():
                zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
                zi.compress_type = i.compress_type
                zi.external_attr = i.external_attr
                zi.create_system = i.create_system
                zw.writestr(zi, new.get(i.filename, None) or zo.read(i.filename))
    r = subprocess.run(['zipalign', '-f', '4', tmp, out], capture_output=True, text=True)
    os.unlink(tmp)
    if r.returncode:
        die('zipalign 失败: ' + r.stdout + r.stderr)
    with zipfile.ZipFile(out) as z:
        if z.testzip() is not None:
            die(f'{out} 校验失败')
        for n, d in new.items():
            if z.read(n) != d:
                die(f'{out} 里的 {n} 和回编结果不一致')
    print(f'jartool: {out}:换了 {", ".join(od)},其余 {len(zo.namelist()) - len(od)} 个条目照原 jar')


def norm(path):
    with open(path) as f:
        return [LABEL.sub(':L', l.rstrip()) for l in f if l.strip()]


def smali_equiv(a, b, rels):
    bad = 0
    for r in rels:
        pa, pb = os.path.join(a, r), os.path.join(b, r)
        if not os.path.isfile(pb):
            print(f'jartool: 回编结果里没有 {r}', file=sys.stderr)
            bad += 1
            continue
        la, lb = norm(pa), norm(pb)
        if la != lb:
            for i, (x, y) in enumerate(zip(la + [''] * len(lb), lb + [''] * len(la))):
                if x != y:
                    print(f'jartool: {r} 第 {i + 1} 条(去空行、标签统一后)不一致:\n    补丁后: {x}\n    回编后: {y}',
                          file=sys.stderr)
                    break
            bad += 1
    if bad:
        die(f'{bad} 个 smali 文件回编后和补丁不一致')
    print(f'jartool: {len(rels)} 个 smali 文件回编后与补丁结果一致(标签名除外)')


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == 'swap-dex':
        swap_dex(*sys.argv[2:5])
    elif len(sys.argv) >= 5 and sys.argv[1] == 'smali-equiv':
        smali_equiv(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        die(__doc__)


if __name__ == '__main__':
    main()
