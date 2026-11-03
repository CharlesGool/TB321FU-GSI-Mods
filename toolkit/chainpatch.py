#!/usr/bin/env python3
"""链式补丁:把 releases/ 里一长串版本镜像换成"最新一版的完整镜像 + 每个旧版相对于它新一版的补丁"。

  chainpatch.py scan    <releases目录>            只扫描,列出会怎么串(不改任何东西)
  chainpatch.py build   <releases目录> [--keep N]  按链生成补丁、逐个还原核对 sha256,核对通过才删被替代的原镜像
  chainpatch.py restore <releases目录> <版本目录名或镜像名片段> <输出.img>   从链头一路倒推还原
  chainpatch.py verify  <releases目录> [N]        从链头随机还原 N 个旧版,核对 sha256

链:按镜像文件的修改时间从新到旧排;erofs 和 ext4 各一条链(两种格式内容完全不同,互相做补丁没有意义)。
补丁方向:patch(k) 把"比它新一版的镜像"变成"版本 k",所以链头(最新一版)永远是完整文件,旧版 = 链头逐级倒推。
中间任何一个补丁丢了,更旧的版本就还原不出来——补丁要和 CHAIN.json 一起备份(进 git / GitHub release)。
xdelta3 参数:-1 -B 512MiB(源窗口 512MiB,新旧版之间删/插过大块内容时必须大窗口,见 docs/FLASH-9008.md)。
zip(早期版本只留了 zip):解出里面的 img 当作该版本镜像;还原得到的是 img,不是 zip。
安全:只有在"补丁已生成 + 用补丁从上一级原文件还原出的东西 sha256 和原镜像一致"之后,才会删被它替代的原文件;
      --keep N(默认 2):最新 N 个版本的完整镜像不删(它们是刷机基准 / 回退用)。
"""
import hashlib, json, os, random, shutil, subprocess, sys, tempfile, time, zipfile

XD = ['xdelta3', '-B', '536870912']
MANIFEST = 'CHAIN.json'
MIN_SIZE = 100 * 1024 * 1024


def sha256(path, bs=1 << 24):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(bs), b''):
            h.update(b)
    return h.hexdigest()


def sha256_zip_member(zpath, member):
    h = hashlib.sha256()
    with zipfile.ZipFile(zpath) as z, z.open(member) as f:
        for b in iter(lambda: f.read(1 << 24), b''):
            h.update(b)
    return h.hexdigest()


def fmt_of(path):
    with open(path, 'rb') as f:
        f.seek(1024); a = f.read(4)
        f.seek(1080); b = f.read(2)
    if a == bytes.fromhex('e2e1f5e0'): return 'erofs'
    if b == b'\x53\xef': return 'ext4'
    return 'unknown'


def log(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)


def scan(root):
    """返回条目列表:{name(相对路径), kind(img|zip), path, member, mtime, size}"""
    items = []
    for d in sorted(os.listdir(root)):
        dp = os.path.join(root, d)
        if not os.path.isdir(dp): continue
        files = {f: os.path.join(dp, f) for f in os.listdir(dp) if os.path.isfile(os.path.join(dp, f))}
        imgs = {f: p for f, p in files.items() if f.endswith('.img') and os.path.getsize(p) >= MIN_SIZE}
        for f, p in imgs.items():
            items.append(dict(name=f'{d}/{f}', kind='img', path=p, mtime=os.path.getmtime(p), size=os.path.getsize(p)))
        for f, p in files.items():
            if f.endswith('.zip') and os.path.getsize(p) >= MIN_SIZE:
                with zipfile.ZipFile(p) as z:
                    mem = [i for i in z.infolist() if i.filename.endswith('.img')]
                if len(mem) != 1: continue
                items.append(dict(name=f'{d}/{f}', kind='zip', path=p, member=mem[0].filename, mtime=os.path.getmtime(p), size=os.path.getsize(p)))
    return items


def plan(root, keep=2):
    items = scan(root)
    # 先给每个 img 算格式;zip 若内容与同目录某 img 相同则标为 dup(只删不做补丁)
    for it in items:
        if it['kind'] == 'img':
            it['fmt'] = fmt_of(it['path']); it['sha'] = None
    for it in items:
        if it['kind'] == 'zip':
            it['dup_of'] = None
    return items


def cmd_scan(root):
    items = plan(root)
    n_img = [i for i in items if i['kind'] == 'img']
    n_zip = [i for i in items if i['kind'] == 'zip']
    tot = sum(i['size'] for i in items) / 2**30
    log(f'镜像 {len(n_img)} 个、zip {len(n_zip)} 个,共 {tot:.1f} GiB')
    for fm in ('erofs', 'ext4', 'unknown'):
        c = [i for i in n_img if i['fmt'] == fm]
        log(f'  {fm}: {len(c)} 个 img')
    for i in n_zip:
        log('  zip:', i['name'], f"{i['size']/2**30:.2f} GiB 内含 {i['member']}")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f'命令失败: {" ".join(cmd)}\n{r.stderr[-500:]}')


def load_manifest(root):
    p = os.path.join(root, MANIFEST)
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {'chains': {}}


def save_manifest(root, m):
    p = os.path.join(root, MANIFEST)
    json.dump(m, open(p + '.tmp', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    os.replace(p + '.tmp', p)


def materialize(it, scratch):
    """拿到条目的 img 文件路径(zip 就解出来)。返回 (路径, 是否临时文件)"""
    if it['kind'] == 'img': return it['path'], False
    out = os.path.join(scratch, os.path.basename(it['member']))
    with zipfile.ZipFile(it['path']) as z, z.open(it['member']) as src, open(out, 'wb') as dst:
        shutil.copyfileobj(src, dst, 1 << 24)
    return out, True


def cmd_build(root, keep=2):
    items = plan(root)
    m = load_manifest(root)
    scratch = tempfile.mkdtemp(prefix='chainpatch-')
    try:
        # 每个条目:镜像格式、sha256(zip 要解出来看格式)
        for it in items:
            p, tmp = materialize(it, scratch) if it['kind'] == 'zip' else (it['path'], False)
            it['fmt'] = fmt_of(p); it['sha'] = sha256(p)
            if tmp: os.remove(p)
            log('指纹', it['name'], it['fmt'], it['sha'][:12])
        # 同内容的只留一个代表,其余标 dup
        seen = {}
        reps = []
        for it in sorted(items, key=lambda i: (i['kind'] != 'img', -i['mtime'])):
            if it['sha'] in seen:
                it['dup_of'] = seen[it['sha']]
            else:
                seen[it['sha']] = it['name']; it['dup_of'] = None; reps.append(it)
        for fm in ('erofs', 'ext4'):
            chain = sorted([i for i in reps if i['fmt'] == fm], key=lambda i: -i['mtime'])
            if not chain: continue
            log(f'== {fm} 链:{len(chain)} 个版本,链头 {chain[0]["name"]}')
            mc = m['chains'].setdefault(fm, {'items': []})
            mc['head'] = chain[0]['name']
            done = {x['name']: x for x in mc['items']}
            for k, it in enumerate(chain):
                ent = done.get(it['name']) or {'name': it['name'], 'sha256': it['sha'], 'size': it['size']}
                ent['sha256'] = it['sha']
                if k == 0:
                    ent['patch'] = None; ent['from'] = None
                else:
                    newer = chain[k - 1]
                    ent['from'] = newer['name']
                    pdir = os.path.dirname(it['path'])
                    pname = os.path.splitext(os.path.basename(it['path']))[0] + f'.from_{os.path.splitext(os.path.basename(newer["path"]))[0][:40]}.chain.xd'
                    ppath = os.path.join(pdir, pname)
                    ent['patch'] = os.path.relpath(ppath, root)
                    if not ent.get('verified'):
                        src_p, src_tmp = materialize(newer, scratch) if (newer['kind'] == 'zip' or not os.path.exists(newer['path'])) else (newer['path'], False)
                        if not os.path.exists(newer['path']) and newer['kind'] == 'img':
                            raise SystemExit(f'上一级原镜像已不在且没有核对过的补丁:{newer["name"]}')
                        tgt_p, tgt_tmp = materialize(it, scratch)
                        log(f'补丁 {it["name"]}  ←  {newer["name"]}')
                        run(XD[:1] + ['-1', '-e', '-f'] + XD[1:] + ['-s', src_p, tgt_p, ppath])
                        out = os.path.join(scratch, 'restored.img')
                        run(XD[:1] + ['-d', '-f'] + XD[1:] + ['-s', src_p, ppath, out])
                        got = sha256(out); os.remove(out)
                        if got != it['sha']:
                            os.remove(ppath)
                            raise SystemExit(f'还原核对失败 {it["name"]}: {got} != {it["sha"]}')
                        ent['patch_sha256'] = sha256(ppath); ent['patch_size'] = os.path.getsize(ppath)
                        ent['verified'] = True
                        log(f'  补丁 {ent["patch_size"]/2**20:.1f} MiB,还原核对通过')
                        for tp, flag in ((src_p, src_tmp), (tgt_p, tgt_tmp)):
                            if flag and os.path.exists(tp): os.remove(tp)
                if ent not in mc['items']: mc['items'].append(ent)
                save_manifest(root, m)
                # 被"本条补丁"替代掉的是:本条目自己的原文件之前一级(newer)——但 newer 还要被它自己的 patch 已验证过,
                # 所以此时 newer 的原文件可以删(newer 自己的补丁在上一轮已核对通过);链头和最新 keep 个除外。
                if k >= 1:
                    newer = chain[k - 1]
                    idx = k - 1
                    if idx >= keep and os.path.exists(newer['path']) and newer.get('_deleted') is None:
                        pe = next(x for x in mc['items'] if x['name'] == newer['name'])
                        if pe.get('verified'):
                            log(f'  删除原文件(已有核对过的补丁): {newer["name"]}')
                            os.remove(newer['path']); newer['_deleted'] = True; pe['deleted'] = True
                            save_manifest(root, m)
            # 链尾最旧的一个:它的补丁已核对,且链上它是最后一个,没有下一级用它;可以删
            last = chain[-1]
            if len(chain) - 1 >= keep and os.path.exists(last['path']):
                le = next(x for x in mc['items'] if x['name'] == last['name'])
                if le.get('verified'):
                    log(f'  删除原文件(链尾): {last["name"]}')
                    os.remove(last['path']); le['deleted'] = True; save_manifest(root, m)
        # 同内容的 dup(通常是 img 的 zip 副本):代表已在链里,代表的内容有备份(代表本身要么在、要么有核对过的补丁)才删
        for it in items:
            if it['dup_of'] and os.path.exists(it['path']):
                rep = next(r for r in reps if r['name'] == it['dup_of'])
                ch = m['chains'][rep['fmt']]['items']
                re_ = next((x for x in ch if x['name'] == rep['name']), None)
                if re_ and (os.path.exists(rep['path']) or re_.get('verified') or re_['name'] == m['chains'][rep['fmt']]['head']):
                    log(f'  删除重复副本: {it["name"]} (内容同 {it["dup_of"]})')
                    os.remove(it['path'])
        save_manifest(root, m)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def restore(root, m, fmt, name, out):
    mc = m['chains'][fmt]
    byname = {x['name']: x for x in mc['items']}
    path = []
    cur = name
    while cur != mc['head']:
        path.append(byname[cur]); cur = byname[cur]['from']
    scratch = tempfile.mkdtemp(prefix='chainrestore-')
    try:
        src = os.path.join(root, mc['head'])
        if not os.path.exists(src):
            raise SystemExit('链头镜像不在了: ' + src)
        for k, ent in enumerate(reversed(path)):
            dst = os.path.join(scratch, f'step{k}.img')
            log('还原', ent['name'])
            run(XD[:1] + ['-d', '-f'] + XD[1:] + ['-s', src, os.path.join(root, ent['patch']), dst])
            if src != os.path.join(root, mc['head']): os.remove(src)
            src = dst
        got = sha256(src)
        want = byname[name]['sha256'] if name in byname else None
        if want and got != want: raise SystemExit(f'核对失败 {got} != {want}')
        shutil.move(src, out); log('完成', out, got[:16])
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def main():
    a = sys.argv[1:]
    if len(a) < 2: print(__doc__); sys.exit(1)
    cmd, root = a[0], os.path.realpath(a[1])
    if cmd == 'scan': cmd_scan(root)
    elif cmd == 'build':
        keep = int(a[a.index('--keep') + 1]) if '--keep' in a else 2
        cmd_build(root, keep)
    elif cmd == 'restore':
        m = load_manifest(root)
        frag, out = a[2], a[3]
        for fm, mc in m['chains'].items():
            hits = [x for x in mc['items'] if frag in x['name']]
            if hits: restore(root, m, fm, hits[0]['name'], out); return
        raise SystemExit('没找到: ' + frag)
    elif cmd == 'verify':
        n = int(a[2]) if len(a) > 2 else 3
        m = load_manifest(root)
        for fm, mc in m['chains'].items():
            cand = [x for x in mc['items'] if x.get('deleted')]
            for x in random.sample(cand, min(n, len(cand))):
                tmp = tempfile.mktemp(suffix='.img', dir='/tmp')
                restore(root, m, fm, x['name'], tmp); os.remove(tmp)
    else: print(__doc__)

if __name__ == '__main__': main()
