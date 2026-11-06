#!/usr/bin/env python3
"""把横屏尺寸的 bootanimation.zip 旋转成竖屏尺寸(TB321FU 面板自然方向是竖屏 1600x2560)。

用法: rotate_bootanim.py <in.zip> <out.zip> [cw|ccw]
- desc.txt 第一行 "W H FPS" 换成 "H W FPS",其余行原样;
- 每帧 PNG 顺时针(cw,默认)或逆时针(ccw)转 90°;
- partN/trim.txt 每行 "wxh+x+y"(帧在画布里的裁剪框)按同样的旋转换算;
- 输出全部 Stored(bootanimation 要求不压缩),条目顺序不变。
纯 Python(zlib 解/编 PNG),不依赖 PIL;只支持 8 位、非隔行 PNG(Pixel 的帧都是)。
"""
import struct
import sys
import zipfile
import zlib

PNG_SIG = b'\x89PNG\r\n\x1a\n'
CH = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def chunks(data):
    assert data[:8] == PNG_SIG, "不是 PNG"
    i = 8
    while i < len(data):
        n, = struct.unpack('>I', data[i:i + 4])
        t = data[i + 4:i + 8]
        yield t, data[i + 8:i + 8 + n]
        i += 12 + n


def mkchunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode(data):
    ihdr = None
    idat = []
    extra = []  # PLTE/tRNS 等要保留的辅助块(在 IDAT 前)
    for t, d in chunks(data):
        if t == b'IHDR':
            ihdr = d
        elif t == b'IDAT':
            idat.append(d)
        elif t in (b'PLTE', b'tRNS', b'gAMA', b'sRGB', b'cHRM', b'iCCP', b'sBIT'):
            extra.append((t, d))
    w, h, bd, ct, cm, fm, il = struct.unpack('>IIBBBBB', ihdr)
    if bd != 8 or il != 0 or ct not in CH:
        raise ValueError(f"不支持的 PNG:bitdepth={bd} colortype={ct} interlace={il}")
    bpp = CH[ct]
    raw = zlib.decompress(b''.join(idat))
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(h):
        f = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if f == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                c = prev[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + paeth(a, prev[x], c)) & 255
        elif f != 0:
            raise ValueError(f"未知过滤器 {f}")
        rows.append(bytes(line))
        prev = line
    return w, h, ct, bpp, rows, extra


def encode(w, h, ct, rows, extra):
    ihdr = struct.pack('>IIBBBBB', w, h, 8, ct, 0, 0, 0)
    raw = b''.join(b'\x00' + r for r in rows)
    out = PNG_SIG + mkchunk(b'IHDR', ihdr)
    for t, d in extra:
        out += mkchunk(t, d)
    out += mkchunk(b'IDAT', zlib.compress(raw, 9)) + mkchunk(b'IEND', b'')
    return out


def rotate_png(data, cw):
    w, h, ct, bpp, rows, extra = decode(data)
    # 像素切片:px[y][x]
    px = [[r[x * bpp:(x + 1) * bpp] for x in range(w)] for r in rows]
    nw, nh = h, w
    out = []
    for ny in range(nh):
        if cw:   # 新(nx,ny) = 旧(x=ny, y=h-1-nx)
            out.append(b''.join(px[h - 1 - nx][ny] for nx in range(nw)))
        else:    # 新(nx,ny) = 旧(x=w-1-ny, y=nx)
            out.append(b''.join(px[nx][w - 1 - ny] for nx in range(nw)))
    return encode(nw, nh, ct, out, extra)


def rotate_trim(line, W, H, cw):
    line = line.strip()
    if not line:
        return line
    wh, x, y = line.split('+')
    w, h = map(int, wh.split('x'))
    x, y = int(x), int(y)
    if cw:
        nx, ny = H - y - h, x
    else:
        nx, ny = y, W - x - w
    return f"{h}x{w}+{nx}+{ny}"


def main():
    src, dst = sys.argv[1], sys.argv[2]
    cw = (sys.argv[3] if len(sys.argv) > 3 else 'cw') == 'cw'
    zin = zipfile.ZipFile(src)
    desc = zin.read('desc.txt').decode().split('\n')
    W, H, fps = desc[0].split()[:3]
    W, H = int(W), int(H)
    if W <= H:
        print(f"desc.txt 已经是竖屏尺寸 {W}x{H},不用转")
        sys.exit(3)
    desc[0] = ' '.join([str(H), str(W)] + desc[0].split()[2:])
    n_png = 0
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_STORED) as zout:
        for info in zin.infolist():
            data = zin.read(info)
            name = info.filename
            if name == 'desc.txt':
                data = '\n'.join(desc).encode()
            elif name.endswith('/trim.txt'):
                data = ('\n'.join(rotate_trim(l, W, H, cw) for l in data.decode().split('\n'))).encode()
            elif name.lower().endswith('.png'):
                data = rotate_png(data, cw)
                n_png += 1
            zi = zipfile.ZipInfo(name, date_time=info.date_time)
            zi.compress_type = zipfile.ZIP_STORED
            zi.external_attr = info.external_attr
            zout.writestr(zi, data)
    print(f"{W}x{H} -> {H}x{W}({'顺时针' if cw else '逆时针'}),转了 {n_png} 帧")


if __name__ == '__main__':
    main()
