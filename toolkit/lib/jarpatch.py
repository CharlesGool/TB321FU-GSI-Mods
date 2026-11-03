#!/usr/bin/env python3
"""给框架 jar(framework.jar / services.jar 等)"反编译 → 打 smali 补丁 → 回编换 dex"流程用的通用工具。

和 apex/jartool.py 是同一套思路(swap-dex / smali-equiv),这里多一个"顺带塞入新 dex"的能力,
给 services.jar 那种"改原来的 classes.dex + 另加一份 classes4.dex(新类)"的场景用。

  assemble <原jar> <apktool回编出的jar> <输出jar> [--swap <名字>]... [--add <名字>=<dex文件>]...
      - --swap 指定要替换的 classes*.dex(= 真的被补丁改到的那几份,从回编 jar 取)。没写 --swap 时
        默认换掉回编 jar 里所有 classes*.dex。没被 --swap 的 dex 保持原 jar 的原样字节不动——这点很重要:
        只有改过的那份 dex 用 apktool 回编版,其余 dex 和资源 / .uau / MANIFEST 全照原 jar
        (顺序、时间戳、压缩方式、external_attr 都不动),这样"没动的部分"逐字节不变。
      - --add 指定的新 dex 插在最后一个 classes*.dex 之后(和原厂多 dex 的排法一致),stored 不压缩,
        用和原 dex 相同的 external_attr。名字要形如 classes4.dex,且原 jar 里不能已经有同名条目。
      - 全部 dex 保持不压缩,最后 zipalign 4;写完再读回校验每个 dex 的内容对得上。
      apktool 回编出的 jar 会丢 MANIFEST、改时间戳,所以不直接拿它当产物,只从它取 dex。

  smali-equiv <打完补丁的smali目录> <回编后再反编译的smali目录> <相对路径>...
      逐个比 smali。baksmali 反编译会按地址重排标签编号(:cond_0 等),补丁里自定义的标签名也会被改,
      所以比较前把所有标签统一成 :L、去掉空行,再比指令 / .line / .catch。不一致就报错。
      用来证明"回编后的 dex 反编译出来,和我们打完补丁的 smali 语义一致",即产物没带进别的改动。
"""
import os
import re
import subprocess
import sys
import zipfile

DEX = re.compile(r'^classes\d*\.dex$')
LABEL = re.compile(r'(?<=[\s{]):[A-Za-z_][A-Za-z0-9_]*\b')
LABELDEF = re.compile(r'^:[A-Za-z_][A-Za-z0-9_]*$')   # 单独一行的标签定义
DOTLINE = re.compile(r'^\.line \d+$')                 # 调试行号指令


def die(msg):
    print(f'jarpatch: 错误: {msg}', file=sys.stderr)
    sys.exit(1)


def assemble(orig, built, out, adds, swaps):
    # adds: [(name, path)]; swaps: 要替换的 dex 名字集合(空=全换)
    add_data = {}
    for name, path in adds:
        if not DEX.match(name):
            die(f'--add 的名字 {name} 不是 classesN.dex')
        d = open(path, 'rb').read()
        if not d.startswith(b'dex\n') or len(d) < 0x70:
            die(f'{path} 不是有效的 dex')
        add_data[name] = d

    with zipfile.ZipFile(orig) as zo, zipfile.ZipFile(built) as zb:
        orig_names = zo.namelist()
        orig_dex = [n for n in orig_names if DEX.match(n)]
        built_dex = {n for n in zb.namelist() if DEX.match(n)}
        if not orig_dex:
            die(f'{orig} 里没有 classes*.dex')
        if not built_dex <= set(orig_dex):
            die(f'回编 jar 里有原 jar 没有的 dex:{sorted(built_dex - set(orig_dex))}')
        swap_set = set(swaps) if swaps else set(built_dex)
        if not swap_set <= built_dex:
            die(f'--swap 指定的 {sorted(swap_set - built_dex)} 不在回编 jar 里')
        for name in add_data:
            if name in orig_names:
                die(f'要新增的 {name} 在原 jar 里已经存在')
        swapped = {n: zb.read(n) for n in swap_set}
        for n, d in swapped.items():
            if not d.startswith(b'dex\n'):
                die(f'回编出的 {n} 不是有效的 dex')
        last_dex = orig_dex[-1]
        dex_attr = zo.getinfo(last_dex).external_attr

        tmp = out + '.unaligned'
        with zipfile.ZipFile(tmp, 'w') as zw:
            for i in zo.infolist():
                zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
                zi.compress_type = i.compress_type
                zi.external_attr = i.external_attr
                zi.create_system = i.create_system
                data = swapped.get(i.filename)
                zw.writestr(zi, data if data is not None else zo.read(i.filename))
                if i.filename == last_dex:
                    for name, d in add_data.items():
                        za = zipfile.ZipInfo(name, date_time=i.date_time)
                        za.compress_type = zipfile.ZIP_STORED
                        za.external_attr = dex_attr
                        za.create_system = i.create_system
                        zw.writestr(za, d)

    r = subprocess.run(['zipalign', '-f', '4', tmp, out], capture_output=True, text=True)
    os.unlink(tmp)
    if r.returncode:
        die('zipalign 失败: ' + r.stdout + r.stderr)

    expect = dict(swapped)
    expect.update(add_data)
    with zipfile.ZipFile(out) as z:
        if z.testzip() is not None:
            die(f'{out} 校验失败')
        for n, d in expect.items():
            if z.read(n) != d:
                die(f'{out} 里的 {n} 和期望的 dex 不一致')
    msg = f'换了 {", ".join(sorted(swap_set))}'
    if add_data:
        msg += f';新增 {", ".join(add_data)}'
    kept = [n for n in orig_dex if n not in swap_set]
    if kept:
        msg += f';原样保留 {", ".join(kept)}'
    print(f'jarpatch: {out}:{msg};其余条目照原 jar')


def norm(path):
    # 比较前把这些和运行语义无关、baksmali 回编时会重排/重编号的东西去掉:空行、单独的标签定义行
    # (:cond_0 / :sense_xxx 这类,位置信息由分支指令那头的 :L 引用保留)、.line 调试行号。
    # 行内的标签引用(if-eqz v0, :xxx)统一成 :L,这样自定义标签名和 baksmali 重命名都不算差异。
    out = []
    for l in open(path):
        s = l.strip()
        # 注释(# …)不进 dex,d8→baksmali 回编后会丢;空行、单独标签、.line 也去掉。
        if not s or s.startswith('#') or LABELDEF.match(s) or DOTLINE.match(s):
            continue
        out.append(LABEL.sub(':L', l.rstrip()))
    return out


def smali_equiv(a, b, rels):
    bad = 0
    for r in rels:
        pa, pb = os.path.join(a, r), os.path.join(b, r)
        if not os.path.isfile(pb):
            print(f'jarpatch: 回编结果里没有 {r}', file=sys.stderr)
            bad += 1
            continue
        la, lb = norm(pa), norm(pb)
        if la != lb:
            for i, (x, y) in enumerate(zip(la + [''] * len(lb), lb + [''] * len(la))):
                if x != y:
                    print(f'jarpatch: {r} 第 {i + 1} 条(去空行、标签统一后)不一致:\n    补丁后: {x}\n    回编后: {y}',
                          file=sys.stderr)
                    break
            bad += 1
    if bad:
        die(f'{bad} 个 smali 文件回编后和补丁不一致')
    print(f'jarpatch: {len(rels)} 个 smali 文件回编后与补丁结果一致(标签名除外)')


def main():
    a = sys.argv[1:]
    if a and a[0] == 'assemble' and len(a) >= 4:
        orig, built, out = a[1], a[2], a[3]
        adds, swaps = [], []
        rest = a[4:]
        while rest:
            if rest[0] == '--add':
                name, _, path = rest[1].partition('=')
                adds.append((name, path))
                rest = rest[2:]
            elif rest[0] == '--swap':
                swaps.append(rest[1])
                rest = rest[2:]
            else:
                die(f'多余的参数: {rest[0]}')
        assemble(orig, built, out, adds, swaps)
    elif a and a[0] == 'smali-equiv' and len(a) >= 4:
        smali_equiv(a[1], a[2], a[3:])
    else:
        die(__doc__)


if __name__ == '__main__':
    main()
