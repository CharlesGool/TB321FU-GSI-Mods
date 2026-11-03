#!/usr/bin/env python3
"""按用户刷机目录标准(flash_select / flash_auto)打 patch 包。

用法:
  mk_patch_pkg.py --version N --note "备注" --device TB321FU \
      --system <新 system.img> --vbmeta-system <vbmeta_system.img> \
      --super1 <super_1_vN.img> --rawprogram <rawprogram_save_persist_unsparse0_vN.xml> \
      --base-version B --base-image <V(B) 的 super_4_vB.img,也就是那一版的 system 镜像> \
      --boot-set <目录,里面有 boot/init_boot/vendor_boot/vbmeta.img> [--include-boot-set] \
      --xdelta-exe <Windows 版 xdelta3.exe> --out <输出目录>

包里的东西(解压到刷机目录根,和 flash_select.bat 同级):
  apply_patch.bat / apply_patch.ps1                 照抄 win/ 下的,流程不变
  tool/xdelta3.exe
  image/super_1_vN.img
  image/rawprogram_save_persist_unsparse0_vN.xml
  image/VN/vbmeta_system.img
  image/VN/{boot,init_boot,vendor_boot,vbmeta}.img   只有 --include-boot-set 时才带
  patch/VN/super_4_vB_to_super_4_vN.patch           xdelta3:super_4_vB.img(源文件)→ super_4_vN.img(合成后)
  patch/VN/manifest.json                            apply_patch.ps1 读它
  补丁说明.md

boot 集(boot/init_boot/vendor_boot/vbmeta)默认不进包:apply_patch.ps1 会从用户刷机目录里别的 Vxx
目录找 sha256 一致的复制过来。换了原厂固件、boot 集变了时必须加 --include-boot-set,
否则用户那边找不到一致的文件,只会退而用旧版本的同名文件(并打"注意")。

检查:xdelta 补丁生成后马上用 xdelta3 -d 还原一遍比 sha256;.bat 必须 CRLF;.ps1 必须 CRLF + UTF-8 BOM
(Windows PowerShell 5 没有 BOM 会按 ANSI 读中文);manifest 里列的文件逐个回算 sha256。
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOOT_SET = ('boot.img', 'init_boot.img', 'vendor_boot.img', 'vbmeta.img')


def die(msg):
    sys.exit(f'[patch-pkg] 错误: {msg}')


def log(msg):
    print(f'[patch-pkg] {msg}')


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()


def check_crlf(p, bom=False):
    b = open(p, 'rb').read()
    if bom and not b.startswith(b'\xef\xbb\xbf'):
        die(f'{p} 没有 UTF-8 BOM')
    lf, crlf, cr = b.count(b'\n'), b.count(b'\r\n'), b.count(b'\r')
    if lf == 0 or crlf != lf or cr != lf:
        die(f'{p} 不是纯 CRLF 行尾(LF {lf},CRLF {crlf},CR {cr})')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--version', type=int, required=True)
    ap.add_argument('--note', required=True)
    ap.add_argument('--device', required=True, help='只用在 7z 文件名里')
    ap.add_argument('--system', required=True)
    ap.add_argument('--vbmeta-system', required=True)
    ap.add_argument('--super1', required=True)
    ap.add_argument('--rawprogram', required=True)
    ap.add_argument('--base-version', type=int, required=True)
    ap.add_argument('--base-image', required=True)
    ap.add_argument('--base-sha256', help='基准镜像应有的 sha256(给了就先核对,防止拿错基准)')
    ap.add_argument('--boot-set', required=True)
    ap.add_argument('--include-boot-set', action='store_true')
    ap.add_argument('--xdelta-exe', required=True)
    ap.add_argument('--xdelta-window', type=int, default=536870912,
                    help='xdelta3 -B 源窗口字节数。默认 512MiB;xdelta3 自带的默认只有 64MiB,新旧镜像之间删掉/插入了多于 64MiB 内容时,后面的数据整体平移,超出窗口就匹配不上,补丁会膨胀到接近整个镜像')
    ap.add_argument('--win-dir', default=os.path.join(HERE, 'win'))
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    n, b = a.version, a.base_version
    if n == b:
        die('新版本号和基准版本号相同')

    for p in (a.system, a.vbmeta_system, a.super1, a.rawprogram, a.base_image, a.xdelta_exe):
        if not os.path.isfile(p):
            die(f'文件不存在: {p}')
    for f in BOOT_SET:
        if not os.path.isfile(os.path.join(a.boot_set, f)):
            die(f'boot 集缺 {f}: {a.boot_set}')
    bat, ps1 = os.path.join(a.win_dir, 'apply_patch.bat'), os.path.join(a.win_dir, 'apply_patch.ps1')
    check_crlf(bat)
    check_crlf(ps1, bom=True)
    if shutil.which('xdelta3') is None or shutil.which('7z') is None:
        die('本机要有 xdelta3 和 7z')

    base_sha = sha(a.base_image)
    if a.base_sha256 and base_sha != a.base_sha256.lower():
        die(f'基准镜像 sha256 是 {base_sha},不是给定的 {a.base_sha256}')
    log(f'基准 V{b}: {a.base_image}  sha256 {base_sha}')

    st = os.path.join(os.path.abspath(a.out), f'9008_v{n}_std')
    shutil.rmtree(st, ignore_errors=True)
    vdir = f'image/V{n}'
    for d in (vdir, f'patch/V{n}', 'tool'):
        os.makedirs(os.path.join(st, d))
    files = {
        f'image/super_1_v{n}.img': a.super1,
        f'image/rawprogram_save_persist_unsparse0_v{n}.xml': a.rawprogram,
        f'{vdir}/vbmeta_system.img': a.vbmeta_system,
    }
    if a.include_boot_set:
        for f in BOOT_SET:
            files[f'{vdir}/{f}'] = os.path.join(a.boot_set, f)
    for k, src in files.items():
        shutil.copyfile(src, os.path.join(st, k))
    shutil.copyfile(a.xdelta_exe, os.path.join(st, 'tool', 'xdelta3.exe'))
    shutil.copyfile(ps1, os.path.join(st, 'apply_patch.ps1'))
    shutil.copyfile(bat, os.path.join(st, 'apply_patch.bat'))

    base_file, result_file = f'super_4_v{b}.img', f'super_4_v{n}.img'
    # 补丁名 = 源文件名 + 合成后的文件名,一眼看出它是拿什么还原出什么
    patch = f'super_4_v{b}_to_super_4_v{n}.patch'
    pp = os.path.join(st, 'patch', f'V{n}', patch)
    log(f'xdelta3 编码 {patch}(要几分钟)')
    subprocess.check_call(['xdelta3', '-e', '-9', '-B', str(a.xdelta_window), '-f', '-s', a.base_image, a.system, pp])
    rec = pp + '.recon'
    subprocess.check_call(['xdelta3', '-d', '-f', '-s', a.base_image, pp, rec])
    sys_sha = sha(a.system)
    if sha(rec) != sys_sha:
        os.remove(rec)
        die('xdelta 还原自检不一致')
    os.remove(rec)
    log(f'xdelta 还原自检通过,补丁 {os.path.getsize(pp)} 字节')

    m = {
        'version': n, 'base': b, 'note': a.note,
        'base_sha256': base_sha, 'super_4_sha256': sys_sha, 'patch': patch,
        'base_file': base_file, 'result_file': result_file,
        'files': {k: sha(os.path.join(st, k)) for k in files},
        'boot_set': {f: sha(os.path.join(a.boot_set, f)) for f in BOOT_SET},
    }
    with open(os.path.join(st, 'patch', f'V{n}', 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
    for k, v in m['files'].items():
        if sha(files[k]) != v:
            die(f'{k} 拷进包后 sha256 变了')
    boot_note = (f'   这一版的 boot / init_boot / vendor_boot / vbmeta 包里自带(原厂固件或 boot 补丁有变化)。\n'
                 if a.include_boot_set else '')
    readme = f"""# V{n} 补丁包

{a.note}

用法(刷机目录 = 有 flash_select.bat 和 image\\、tool\\ 的那个目录):
1. 把本压缩包全部解压到刷机目录根, 同名文件覆盖。
2. 双击 apply_patch.bat。它会用 image\\super_4_v{b}.img 还原出 image\\super_4_v{n}.img(sha256 校验),
   并凑齐 image\\V{n} 里的 boot / init_boot / vendor_boot / vbmeta / vbmeta_system。
{boot_note}3. 运行 flash_select.bat 选 V{n} 刷入(不清 data)。

源文件: {base_file}(V{b} 的 system), sha256 {m['base_sha256']}
合成后: {result_file}, sha256 {m['super_4_sha256']}
补丁: patch\\V{n}\\{patch}
"""
    with open(os.path.join(st, '补丁说明.md'), 'w', encoding='utf-8') as f:
        f.write(readme)
    # 7z 名也带上源文件和合成后的文件名
    out7z = os.path.join(os.path.abspath(a.out), f'{a.device}_super_4_v{b}_to_super_4_v{n}_9008patch.7z')
    if os.path.exists(out7z):
        os.remove(out7z)
    subprocess.check_call(['7z', 'a', '-mx=1', out7z, '.'], cwd=st, stdout=subprocess.DEVNULL)
    s7 = sha(out7z)
    with open(out7z + '.sha256', 'w') as f:
        f.write(f'{s7}  {os.path.basename(out7z)}\n')
    log(f'写出 {out7z}({os.path.getsize(out7z)} 字节)sha256 {s7}')
    log(f'展开的包内容在 {st}')
    print(f"flash_select.ps1 的 $notes 备注行:    {n} = '{a.note}'")


if __name__ == '__main__':
    main()
