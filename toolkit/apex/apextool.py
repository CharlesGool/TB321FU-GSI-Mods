#!/usr/bin/env python3
"""Mainline APEX 解包 / 改 payload / 重签 工具。

APEX 是个 zip:apex_payload.img(ext4,带 AVB hashtree footer)+ apex_pubkey(验 payload 的 AVB 公钥)
+ apex_manifest.pb 等,整个 zip 再用 APK 签名。Compressed APEX(CAPEX)外面多一层壳,
里面的 original_apex 才是完整的 APEX。

子命令:
  info    <apex>                               看类型、zip 条目、payload 的 AVB 信息和文件列表
  extract <apex> <payload内路径> <输出文件>     从 APEX/CAPEX 的 payload 里取出一个文件
  repack  <apex> <输出apex> --replace 路径=文件 ... --avb-key PEM --cert X509 --pk8 PK8
          替换 payload 里的文件(保留属主/权限/xattr/时间)→ 重做 hashtree footer → 换 apex_pubkey
          → zipalign → apksigner 重签。输出总是完整 APEX(不复原 CAPEX 外壳)。结束时自动跑 verify。
  verify  <新apex> --orig <原apex> --avb-key PEM [--changed 路径[=文件] ...]
          核对:APK 签名、payload AVB 签名和 apex_pubkey 对得上、hashtree 参数和原版一致、
          zip 里除 payload/pubkey/签名外的条目和原版逐字节一致、payload 里除 --changed 外的文件
          内容和属主/权限/xattr 和原版一致。

全局参数 --avbtool 指定 avbtool.py(默认用本仓库 toolkit/avb/avbtool.py)。
需要的外部工具:debugfs、e2fsck、resize2fs(e2fsprogs)、zipalign、apksigner。

注意:
  - payload 的 ext4 一般带 shared_blocks 特性,内核不让 RW 挂载,所以全程用 debugfs 改镜像。
  - debugfs 命令出错时退出码也是 0,这里把 stderr 里除版本横幅外的任何输出都当错误。
  - 不要用它改 APEX 里 app/、priv-app/ 下的 APK:那些包由 PackageManager 按普通 APK 安装,
    换签名会被签名延续性检查拒掉(见 patches/required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/README.md)。
"""
import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_AVBTOOL = os.path.join(os.path.dirname(HERE), 'avb', 'avbtool.py')
AVBTOOL = DEFAULT_AVBTOOL
# 签名时去掉的条目:旧签名、source stamp(stamp 签名块重签后就没了,留着 stamp-cert-sha256 只会让校验报不一致)
DROP = re.compile(r'^(META-INF/|stamp-cert-sha256$)')


def die(msg):
    print(f'apextool: 错误: {msg}', file=sys.stderr)
    sys.exit(1)


def log(msg):
    print(f'apextool: {msg}', flush=True)


def run(cmd, ok=(0,), what=None):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode not in ok:
        out = (r.stdout + r.stderr).strip().splitlines()
        die(f'{what or cmd[0]} 失败(退出码 {r.returncode}):\n    ' + '\n    '.join(out[-20:]))
    return r


def avb(*args, ok=(0,)):
    return run([sys.executable, '-I', AVBTOOL, *args], ok=ok, what=f'avbtool {args[0]}')


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


# ---------------------------------------------------------------- APEX 容器

def open_inner(apex, tmp):
    """返回完整 APEX 的路径(CAPEX 时解出 original_apex)和类型"""
    if not zipfile.is_zipfile(apex):
        die(f'{apex} 不是 zip,不是 APEX')
    with zipfile.ZipFile(apex) as z:
        names = z.namelist()
        if 'apex_payload.img' in names:
            return apex, 'apex'
        if 'original_apex' in names:
            inner = os.path.join(tmp, 'original_apex.apex')
            with z.open('original_apex') as s, open(inner, 'wb') as d:
                shutil.copyfileobj(s, d, 1 << 20)
            with zipfile.ZipFile(inner) as zi:
                if 'apex_payload.img' not in zi.namelist():
                    die(f'{apex} 的 original_apex 里没有 apex_payload.img')
            return inner, 'capex'
    die(f'{apex} 里既没有 apex_payload.img 也没有 original_apex,不认识的格式')


def extract_entry(apex, name, out):
    with zipfile.ZipFile(apex) as z, z.open(name) as s, open(out, 'wb') as d:
        shutil.copyfileobj(s, d, 1 << 20)


def entry_offsets(apex):
    """{条目名: (数据偏移, 压缩方式)}"""
    res = {}
    with zipfile.ZipFile(apex) as z, open(apex, 'rb') as f:
        for i in z.infolist():
            f.seek(i.header_offset)
            h = f.read(30)
            n, e = struct.unpack('<HH', h[26:30])
            res[i.filename] = (i.header_offset + 30 + n + e, i.compress_type)
    return res


# ---------------------------------------------------------------- payload(ext4,debugfs)

class Payload:
    def __init__(self, img):
        self.img = img

    def dbg(self, cmd, write=False, script=None):
        args = ['debugfs']
        if write:
            args.append('-w')
        if script:
            args += ['-f', script]
        else:
            args += ['-R', cmd]
        args.append(self.img)
        r = subprocess.run(args, capture_output=True)
        err = [l for l in r.stderr.decode(errors='replace').splitlines()
               if l.strip() and not l.startswith('debugfs ')]
        if r.returncode != 0 or err:
            die(f'debugfs {"-f " + script if script else cmd!r} 出错:\n    ' + '\n    '.join(err[-20:]))
        return r.stdout

    def ls(self, d):
        out = []
        for line in self.dbg(f'ls -p "{d}"').decode(errors='surrogateescape').splitlines():
            if not line.startswith('/'):
                continue
            f = line.split('/')
            # /inode/mode/uid/gid/name/size/  (文件名里不会有 /)
            ino, mode, uid, gid, name = f[1], f[2], f[3], f[4], f[5]
            if name in ('.', '..') or ino == '0':
                continue
            out.append((name, int(mode, 8), int(uid), int(gid)))
        return out

    def xattrs(self, p, tmp):
        res = {}
        text = self.dbg(f'ea_list "{p}"').decode(errors='surrogateescape')
        for key in re.findall(r'^\s+(\S+) \(\d+\)', text, re.M):
            vf = os.path.join(tmp, 'ea.bin')
            self.dbg(f'ea_get -f "{vf}" "{p}" {key}')
            with open(vf, 'rb') as f:
                res[key] = f.read()
            os.unlink(vf)
        return res

    def stat(self, p):
        return self.dbg(f'stat "{p}"').decode(errors='surrogateescape')

    def times(self, p):
        """{'atime': 秒, ...},只取秒,纳秒不管"""
        return {k: int(v, 16) for k, v in re.findall(r'^\s*(ctime|atime|mtime|crtime): 0x([0-9a-f]+)', self.stat(p), re.M)}

    def dump(self, p, out):
        self.dbg(f'dump "{p}" "{out}"')

    def blocks(self, p):
        return set(self.dbg(f'blocks "{p}"').split())

    def stats(self):
        t = self.dbg('stats').decode(errors='surrogateescape')
        g = lambda k: int(re.search(rf'^{k}:\s+(\d+)', t, re.M).group(1))
        feats = re.search(r'^Filesystem features:\s+(.*)$', t, re.M).group(1).split()
        return {'block_size': g('Block size'), 'block_count': g('Block count'),
                'free_blocks': g('Free blocks'), 'features': feats}

    def walk(self, tmp, hash_files=True):
        """{相对路径: {mode,uid,gid,xattrs,sha256|link}},'' 是根目录"""
        res = {}
        root_x = self.xattrs('/', tmp)
        res[''] = {'mode': None, 'uid': None, 'gid': None, 'xattrs': root_x}
        stack = ['']
        while stack:
            d = stack.pop()
            for name, mode, uid, gid in self.ls('/' + d):
                p = f'{d}/{name}' if d else name
                ent = {'mode': mode, 'uid': uid, 'gid': gid, 'xattrs': self.xattrs('/' + p, tmp)}
                kind = mode & 0o170000
                if kind == 0o040000:
                    stack.append(p)
                elif kind == 0o100000 and hash_files:
                    out = os.path.join(tmp, 'dump.bin')
                    self.dump('/' + p, out)
                    ent['sha256'] = sha256_file(out)
                    ent['size'] = os.path.getsize(out)
                    os.unlink(out)
                elif kind == 0o120000:
                    m = re.search(r'Fast link dest: "(.*)"', self.stat('/' + p))
                    if m:
                        ent['link'] = m.group(1)
                    else:
                        out = os.path.join(tmp, 'dump.bin')
                        self.dump('/' + p, out)
                        ent['link'] = open(out, 'rb').read().decode(errors='surrogateescape')
                        os.unlink(out)
                res[p] = ent
        return res


def fsck(img, fix=False):
    if fix:
        r = run(['e2fsck', '-fy', img], ok=(0, 1), what='e2fsck -fy')
        if r.returncode == 1:
            log('e2fsck 修正了文件系统计数(debugfs 改完后常见)')
    run(['e2fsck', '-fn', img], what='e2fsck -fn(改完后文件系统不干净)')


def compare_trees(before, after, changed):
    """changed: {路径: 期望 sha256 或 None(不查内容)}。返回问题列表"""
    bad = []
    for p in sorted(set(before) | set(after)):
        if p not in after:
            bad.append(f'少了 {p}')
            continue
        if p not in before:
            bad.append(f'多了 {p}')
            continue
        b, a = before[p], after[p]
        for k in ('mode', 'uid', 'gid', 'xattrs', 'link'):
            if b.get(k) != a.get(k):
                bad.append(f'{p} 的 {k} 变了: {b.get(k)!r} -> {a.get(k)!r}')
        if p in changed:
            if changed[p] and a.get('sha256') != changed[p]:
                bad.append(f'{p} 的内容和要放进去的文件不一致')
        elif b.get('sha256') != a.get('sha256'):
            bad.append(f'{p} 的内容变了(没要求改它)')
    return bad


# ---------------------------------------------------------------- AVB footer

def footer_params(img):
    t = avb('info_image', '--image', img).stdout
    if t.count('Hashtree descriptor:') != 1:
        die(f'payload 的 vbmeta 里 hashtree descriptor 不是正好一个,不认识的布局:\n{t}')
    g = lambda k: re.search(rf'^\s*{k}:[ \t]*(.*)$', t, re.M).group(1).strip()
    return {
        'algorithm': g('Algorithm'),
        'hash_algorithm': g('Hash Algorithm'),
        'salt': g('Salt'),
        'partition_name': g('Partition Name'),
        'block_size': int(g('Data Block Size').split()[0]),
        'fec_roots': int(g('FEC num roots')),
        'rollback_index': int(g('Rollback Index')),
        'pubkey_sha1': g('Public key \\(sha1\\)'),
        'props': re.findall(r"^\s*Prop: (\S+) -> '(.*)'$", t, re.M),
    }


def pubkey_of(key, tmp):
    out = os.path.join(tmp, 'apex_pubkey')
    avb('extract_public_key', '--key', key, '--output', out)
    return out


# ---------------------------------------------------------------- 子命令

def cmd_info(a):
    with tempfile.TemporaryDirectory(dir=a.tmpdir) as tmp:
        inner, kind = open_inner(a.apex, tmp)
        print(f'类型: {kind}' + ('(Compressed APEX,内层 original_apex)' if kind == 'capex' else ''))
        print('zip 条目(偏移 / 压缩):')
        for n, (off, ct) in entry_offsets(inner).items():
            print(f'  {n:32s} {off:>10d}  {"stored" if ct == 0 else "deflate"}')
        img = os.path.join(tmp, 'payload.img')
        extract_entry(inner, 'apex_payload.img', img)
        print(avb('info_image', '--image', img).stdout)
        print('payload 文件:')
        for p, e in sorted(Payload(img).walk(tmp, hash_files=False).items()):
            if p:
                print(f'  {e["mode"]:07o} {e["uid"]:>5}:{e["gid"]:<5} {p}')


def cmd_extract(a):
    p = a.path.strip('/')
    with tempfile.TemporaryDirectory(dir=a.tmpdir) as tmp:
        inner, kind = open_inner(a.apex, tmp)
        img = os.path.join(tmp, 'payload.img')
        extract_entry(inner, 'apex_payload.img', img)
        pl = Payload(img)
        d, name = os.path.split(p)
        ent = [e for e in pl.ls('/' + d) if e[0] == name]
        if not ent:
            die(f'payload 里没有 {p}')
        if ent[0][1] & 0o170000 != 0o100000:
            die(f'payload 里的 {p} 不是普通文件')
        pl.dump('/' + p, a.out)
        if os.path.getsize(a.out) == 0:
            die(f'取出来的 {p} 是空的')
        log(f'{p} -> {a.out}({os.path.getsize(a.out)} 字节,sha256 {sha256_file(a.out)[:16]})')


def cmd_repack(a):
    for f in (a.avb_key, a.cert, a.pk8):
        if not os.path.isfile(f):
            die(f'找不到 {f}')
    repl = {}
    for spec in a.replace:
        if '=' not in spec:
            die(f'--replace 要写成 payload内路径=本地文件: {spec}')
        p, f = spec.split('=', 1)
        p = p.strip('/')
        if not os.path.isfile(f) or os.path.getsize(f) == 0:
            die(f'要放进 payload 的文件不存在或是空的: {f}')
        repl[p] = os.path.abspath(f)
    if not repl:
        die('没给 --replace')

    with tempfile.TemporaryDirectory(dir=a.tmpdir) as tmp:
        inner, kind = open_inner(a.apex, tmp)
        log(f'输入是 {kind},用内层完整 APEX 重做' if kind == 'capex' else '输入是完整 APEX')
        orig_img = os.path.join(tmp, 'payload.orig.img')
        extract_entry(inner, 'apex_payload.img', orig_img)
        fp = footer_params(orig_img)
        img = os.path.join(tmp, 'payload.img')
        shutil.copyfile(orig_img, img)
        avb('erase_footer', '--image', img)          # 去掉 hashtree 和 vbmeta,剩纯 ext4
        fsck(img)
        pl = Payload(img)
        before = pl.walk(tmp)
        for p in repl:
            if p not in before:
                die(f'payload 里没有 {p}(只能替换已有文件)')
            if before[p]['mode'] & 0o170000 != 0o100000:
                die(f'payload 里的 {p} 不是普通文件')

        # 空间:payload 通常只留几个空闲块。不够就扩镜像(resize2fs 支持 shared_blocks 的镜像)
        st = pl.stats()
        bs = st['block_size']
        others = set()
        for p, e in before.items():
            if p not in repl and e['mode'] and e['mode'] & 0o170000 == 0o100000:
                others |= pl.blocks('/' + p)
        old_blocks = set()
        for p in repl:
            old_blocks |= pl.blocks('/' + p)
        shared = old_blocks & others
        need = sum(-(-os.path.getsize(f) // bs) for f in repl.values()) - len(old_blocks - others) \
            + len(shared) + 8 * len(repl)
        if st['free_blocks'] < need:
            grow = need - st['free_blocks'] + 16
            log(f'payload 空闲 {st["free_blocks"]} 块,需要约 {need} 块,扩 {grow} 块')
            os.truncate(img, (st['block_count'] + grow) * bs)
            run(['resize2fs', img], what='resize2fs')
            fsck(img)
        if shared:
            # 要删的文件和别的文件共用数据块:直接 rm 会把别人的块也标成空闲,先拆开
            log(f'{len(shared)} 个数据块和其它文件共用,先 e2fsck -E unshare_blocks')
            run(['e2fsck', '-fy', '-E', 'unshare_blocks', img], ok=(0, 1), what='e2fsck unshare_blocks')
            fsck(img)

        for p, f in repl.items():
            e = before[p]
            times = pl.times('/' + p)
            d, name = os.path.split(p)
            script = os.path.join(tmp, 'dbg.txt')
            lines = [f'cd "/{d}"', f'rm "{name}"', f'write "{f}" "{name}"',
                     f'sif "{name}" mode 0{e["mode"]:o}', f'sif "{name}" uid {e["uid"]}', f'sif "{name}" gid {e["gid"]}']
            lines += [f'sif "{name}" {k} @{v}' for k, v in times.items()]
            for i, (k, v) in enumerate(e['xattrs'].items()):
                vf = os.path.join(tmp, f'xattr{i}.bin')
                with open(vf, 'wb') as fh:
                    fh.write(v)
                lines.append(f'ea_set -f "{vf}" "{name}" {k}')
            with open(script, 'w') as fh:
                fh.write('\n'.join(lines) + '\n')
            pl.dbg(None, write=True, script=script)
            log(f'payload: 换了 {p}({os.path.getsize(f)} 字节,保留 {e["mode"]:o} {e["uid"]}:{e["gid"]} '
                f'xattr {",".join(e["xattrs"]) or "无"})')
        fsck(img, fix=True)

        after = pl.walk(tmp)
        bad = compare_trees(before, after, {p: sha256_file(f) for p, f in repl.items()})
        if bad:
            die('改完的 payload 和预期不符:\n    ' + '\n    '.join(bad))
        for p, f in repl.items():                    # 再单独 dump 回来逐字节比一次
            back = os.path.join(tmp, 'back.bin')
            pl.dump('/' + p, back)
            with open(back, 'rb') as x, open(f, 'rb') as y:
                if x.read() != y.read():
                    die(f'从 payload 读回的 {p} 和放进去的文件不一致')
            os.unlink(back)
        log(f'payload 文件树核对通过:{len(before)} 项,只有 {", ".join(repl)} 内容变了')

        # AVB:沿用原 footer 的 salt / 分区名 / hash 算法 / prop,只换签名 key
        args = ['add_hashtree_footer', '--image', img, '--partition_name', fp['partition_name'],
                '--hash_algorithm', fp['hash_algorithm'], '--salt', fp['salt'],
                '--block_size', str(fp['block_size']), '--algorithm', a.avb_algorithm, '--key', a.avb_key,
                '--rollback_index', str(fp['rollback_index'])]
        for k, v in fp['props']:
            args += ['--prop', f'{k}:{v}']
        if fp['fec_roots'] == 0:
            args.append('--do_not_generate_fec')
        avb(*args)
        avb('verify_image', '--image', img, '--key', a.avb_key)
        pub = pubkey_of(a.avb_key, tmp)
        log(f'payload 重签完成(hashtree {fp["hash_algorithm"]},{a.avb_algorithm})')

        # 外层 zip:条目和顺序沿用原 APEX,换 payload 和 apex_pubkey,去掉旧签名和 stamp
        unsigned = os.path.join(tmp, 'unsigned.apex')
        with zipfile.ZipFile(inner) as zin, zipfile.ZipFile(unsigned, 'w') as zout:
            for info in zin.infolist():
                if DROP.match(info.filename):
                    continue
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                if info.filename == 'apex_payload.img':
                    src = img
                elif info.filename == 'apex_pubkey':
                    src = pub
                else:
                    zout.writestr(zi, zin.read(info.filename))
                    continue
                with open(src, 'rb') as fh:
                    zout.writestr(zi, fh.read())
        aligned = os.path.join(tmp, 'aligned.apex')
        run(['zipalign', '-f', '4096', unsigned, aligned], what='zipalign')
        out = os.path.abspath(a.out)
        if os.path.exists(out):
            os.unlink(out)
        # --alignment-preserved true:保住 zipalign 的 4096 对齐。apksigner 默认(false)会把所有条目
        # 重新按 4 字节对齐,抹掉 apex_payload.img 的 4096 页对齐(apexd 要求 payload 4096 对齐),
        # 产物就卡在后面的 off % 4096 校验(数据偏移 128)。见下方 do_verify 的对齐检查。
        run(['apksigner', 'sign', '--key', a.pk8, '--cert', a.cert,
             '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true', '--v3-signing-enabled', 'true',
             '--alignment-preserved', 'true',
             '--out', out, aligned], what='apksigner sign')
        if os.path.exists(out + '.idsig'):
            os.unlink(out + '.idsig')
        log(f'输出 {out}({os.path.getsize(out)} 字节)')

        do_verify(out, a.apex, a.avb_key, {p: f for p, f in repl.items()}, a.tmpdir)


def do_verify(new, orig, key, changed, tmpdir):
    """changed: {路径: 本地文件或 None}"""
    with tempfile.TemporaryDirectory(dir=tmpdir) as tmp:
        r = run(['apksigner', 'verify', '-v', new], what='apksigner verify')
        schemes = re.findall(r'Verified using (v\d) scheme.*: true', r.stdout)
        log(f'APK 签名通过({"/".join(schemes)})')

        with zipfile.ZipFile(new) as z:
            if 'apex_payload.img' not in z.namelist():
                die('新 APEX 里没有 apex_payload.img')
        oinner, kind = open_inner(orig, tmp)
        offs = entry_offsets(new)
        off, ct = offs['apex_payload.img']
        if ct != zipfile.ZIP_STORED:
            die('apex_payload.img 被压缩了,apexd 要求不压缩')
        if off % 4096:
            die(f'apex_payload.img 数据偏移 {off} 没有 4096 对齐')
        with zipfile.ZipFile(new) as zn, zipfile.ZipFile(oinner) as zo:
            nn = [n for n in zn.namelist() if not DROP.match(n)]
            on = [n for n in zo.namelist() if not DROP.match(n)]
            if sorted(nn) != sorted(on):
                die(f'zip 条目和原版不一样:\n    新 {nn}\n    原 {on}')
            for n in nn:
                if n in ('apex_payload.img', 'apex_pubkey'):
                    continue
                if zn.read(n) != zo.read(n):
                    die(f'zip 条目 {n} 和原版不一样')
        log(f'zip 条目核对通过:{", ".join(n for n in nn if n not in ("apex_payload.img", "apex_pubkey"))} 与原版逐字节一致')

        nimg = os.path.join(tmp, 'new.img')
        oimg = os.path.join(tmp, 'orig.img')
        extract_entry(new, 'apex_payload.img', nimg)
        extract_entry(oinner, 'apex_payload.img', oimg)
        avb('verify_image', '--image', nimg, '--key', key)
        npar, opar = footer_params(nimg), footer_params(oimg)
        pub = pubkey_of(key, tmp)
        pdata = open(pub, 'rb').read()
        with zipfile.ZipFile(new) as z:
            if z.read('apex_pubkey') != pdata:
                die('apex_pubkey 不是这把 AVB key 的公钥')
        if npar['pubkey_sha1'] != hashlib.sha1(pdata).hexdigest():
            die('payload vbmeta 里的公钥和 apex_pubkey 不一致')
        for k in ('hash_algorithm', 'salt', 'partition_name', 'block_size', 'props', 'rollback_index'):
            if npar[k] != opar[k]:
                die(f'hashtree 参数 {k} 和原版不同: {npar[k]!r} vs {opar[k]!r}')
        log('payload AVB 校验通过,公钥与 apex_pubkey 一致,hashtree 参数(salt/分区名/算法/prop)与原版一致')

        for img in (nimg, oimg):
            avb('erase_footer', '--image', img)
        fsck(nimg)
        a = Payload(nimg).walk(tmp)
        b = Payload(oimg).walk(tmp)
        exp = {}
        for p, f in changed.items():
            exp[p.strip('/')] = sha256_file(f) if f else None
        bad = compare_trees(b, a, exp)
        for p in exp:
            if p in a and p in b and a[p].get('sha256') == b[p].get('sha256'):
                bad.append(f'{p} 应该被改过,但和原版一样')
        if bad:
            die('payload 和原版的差异不符合预期:\n    ' + '\n    '.join(bad))
        log(f'payload 文件树核对通过:{len(a)} 项,除 {", ".join(exp) or "(无)"} 外内容/属主/权限/xattr 与原版一致')


def cmd_verify(a):
    changed = {}
    for spec in a.changed or []:
        p, _, f = spec.partition('=')
        changed[p] = f or None
    do_verify(a.apex, a.orig, a.avb_key, changed, a.tmpdir)
    log('全部通过')


def main():
    global AVBTOOL
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--avbtool', default=DEFAULT_AVBTOOL)
    ap.add_argument('--tmpdir', default=None, help='临时目录的父目录(默认系统临时目录)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('info'); s.add_argument('apex'); s.set_defaults(fn=cmd_info)
    s = sub.add_parser('extract'); s.add_argument('apex'); s.add_argument('path'); s.add_argument('out')
    s.set_defaults(fn=cmd_extract)
    s = sub.add_parser('repack'); s.add_argument('apex'); s.add_argument('out')
    s.add_argument('--replace', action='append', default=[], metavar='路径=文件')
    s.add_argument('--avb-key', required=True, help='payload 的 AVB 私钥(PEM)')
    s.add_argument('--avb-algorithm', default='SHA256_RSA4096')
    s.add_argument('--cert', required=True, help='APK 签名证书(x509 PEM)')
    s.add_argument('--pk8', required=True, help='APK 签名私钥(pk8)')
    s.set_defaults(fn=cmd_repack)
    s = sub.add_parser('verify'); s.add_argument('apex'); s.add_argument('--orig', required=True)
    s.add_argument('--avb-key', required=True)
    s.add_argument('--changed', action='append', metavar='路径[=文件]')
    s.set_defaults(fn=cmd_verify)
    a = ap.parse_args()
    AVBTOOL = a.avbtool
    if not os.path.isfile(AVBTOOL):
        die(f'找不到 avbtool: {AVBTOOL}')
    for t in ('debugfs', 'e2fsck'):
        if not shutil.which(t):
            die(f'缺工具 {t}(e2fsprogs)')
    a.fn(a)


if __name__ == '__main__':
    main()
