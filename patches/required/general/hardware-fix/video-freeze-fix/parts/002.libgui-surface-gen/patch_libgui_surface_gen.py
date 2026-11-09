#!/usr/bin/env python3
"""
修 Pixel A17 GSI 在 HIDL Codec2 vendor 上 "视频卡住、声音继续" 的问题。

补丁内容(只改 4 字节):
    libgui.so  Surface::disconnect() 里的  `mGenerationNumber = 0;`  -> NOP
恢复成 A16 及以前的行为: disconnect 不清 Surface 缓存的 generation。

定位方式(不硬编码偏移, 换 build 也能用, 任何一步不唯一就中止):
  1. 从 .dynsym 找 Surface::setGenerationNumber(uint32_t), 函数体内唯一一条
     32 位 STR(unsigned offset) 的偏移 = mGenerationNumber 字段偏移 (A17 当前 build = 0x3b0)
  2. 从 .dynsym 找 Surface::disconnect(int, DisconnectMode), 函数体内
     `str wzr, [xN, #<字段偏移>]` 必须恰好 1 条
  3. 把那条指令换成 NOP (d503201f), 其余字节原样

用法:
  python3 patch_libgui_surface_gen.py <libgui.so 输入> <输出>          # 打补丁
  python3 patch_libgui_surface_gen.py --check <libgui.so>              # 只检查状态
依赖: pyelftools (pip install pyelftools)
32 位 /system/lib/libgui.so 是 ARM32, 本脚本只处理 arm64 的 /system/lib64/libgui.so;
32 位进程(几乎没有 32 位 app 播视频)不受此补丁影响。
"""
import sys, struct, hashlib
from elftools.elf.elffile import ELFFile

SYM_SETGEN = "_ZN7android7Surface19setGenerationNumberEj"
SYM_DISCONNECT = "_ZN7android7Surface10disconnectEiNS_22IGraphicBufferProducer14DisconnectModeE"
NOP = 0xD503201F


def die(msg):
    print("ERROR:", msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    data = bytearray(open(path, "rb").read())
    with open(path, "rb") as f:
        elf = ELFFile(f)
        if elf["e_machine"] != "EM_AARCH64":
            die(f"{path} 不是 arm64 ELF ({elf['e_machine']})")
        dynsym = elf.get_section_by_name(".dynsym")
        syms = {}
        for s in dynsym.iter_symbols():
            if s.name in (SYM_SETGEN, SYM_DISCONNECT) and s["st_value"]:
                syms[s.name] = (s["st_value"], s["st_size"])
        segs = [(p["p_vaddr"], p["p_offset"], p["p_filesz"])
                for p in elf.iter_segments() if p["p_type"] == "PT_LOAD"]
    for name in (SYM_SETGEN, SYM_DISCONNECT):
        if name not in syms:
            die(f"找不到符号 {name}(这个 libgui 不是 A17 那套实现? 先确认问题是否存在)")

    def v2o(va):
        for vaddr, off, sz in segs:
            if vaddr <= va < vaddr + sz:
                return va - vaddr + off
        die(f"vaddr {va:#x} 不在任何 PT_LOAD 里")

    def insns(name):
        va, size = syms[name]
        off = v2o(va)
        return [(off + i, struct.unpack_from("<I", data, off + i)[0]) for i in range(0, size, 4)]

    return data, insns


def is_str32_uoff(insn):          # STR Wt, [Xn, #imm]  (unsigned offset)
    return (insn & 0xFFC00000) == 0xB9000000


def field_off(insn):
    return ((insn >> 10) & 0xFFF) * 4


def analyse(path):
    data, insns = load(path)
    stores = [(o, i) for o, i in insns(SYM_SETGEN) if is_str32_uoff(i)]
    if len(stores) != 1:
        die(f"setGenerationNumber 里 32 位 STR 有 {len(stores)} 条, 预期 1 条, 中止")
    gen_off = field_off(stores[0][1])

    dis = insns(SYM_DISCONNECT)
    hits = [(o, i) for o, i in dis
            if is_str32_uoff(i) and (i & 0x1F) == 31 and field_off(i) == gen_off]
    return data, gen_off, hits, dis


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        data, gen_off, hits, dis = analyse(sys.argv[2])
        print(f"mGenerationNumber 偏移 = {gen_off:#x}")
        if len(hits) == 1:
            print(f"未打补丁: Surface::disconnect 在文件偏移 {hits[0][0]:#x} 清零 generation")
        elif not hits:
            print("Surface::disconnect 里没有清零 generation 的指令(已打补丁, 或此版本没有这个问题)")
        else:
            print(f"异常: 命中 {len(hits)} 处")
        return
    if len(sys.argv) != 3:
        die(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    data, gen_off, hits, _ = analyse(src)
    if len(hits) != 1:
        die(f"Surface::disconnect 里 `str wzr,[xN,#{gen_off:#x}]` 命中 {len(hits)} 处, 预期 1 处, 中止")
    off, old = hits[0]
    struct.pack_into("<I", data, off, NOP)
    open(dst, "wb").write(data)
    print(f"mGenerationNumber 偏移 {gen_off:#x}; 文件偏移 {off:#x}: {old:08x} -> {NOP:08x} (NOP)")
    print("sha256 in :", hashlib.sha256(open(src, 'rb').read()).hexdigest())
    print("sha256 out:", hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
