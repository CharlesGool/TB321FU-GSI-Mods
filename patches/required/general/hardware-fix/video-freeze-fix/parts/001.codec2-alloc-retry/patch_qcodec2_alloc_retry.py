#!/usr/bin/env python3
"""
修 TB321FU(高通 A14 vendor) 刷 Pixel 提取 GSI 后, X 等 app 刷视频时
"预加载好的视频滑过去后画面卡住、声音继续、拖进度条恢复" 的问题(原因 #2)。

补丁内容(只改 4 字节):
    /vendor/lib64/libqcodec2_v4l2codec.so
    QC2V4l2Decoder::DecoderOutputAllocator::handleOutputBufferAllocation()
    超时(C2_TIMED_OUT) 分支里:
        ldr x9, [x8, #0x280]      ; 阈值 private_max_retry_alloc_output_timeout (=1000ms)
        cbz x9, REPOST            ; 阈值为 0 -> "不限时", 继续重试
    改成
        b   REPOST                ; 永远继续重试(150ms 一次), 不再 "距上次输入 >1s 就放弃"
等效于把 vendor 自带的阈值设成 0("no time limitation for output buffer allocation")。

定位方式(不硬编码偏移, 任何一步不唯一就中止):
  1. .dynsym 找 handleOutputBufferAllocation
  2. 函数体内找 "ldr Xt,[Xn,#K]; cbz Xt,T" 和 "ldr Xs,[Xm,#K-8]; cbz Xs,T" 成对出现
     (阈值字段 K=0x280, 上次输入时间字段 K-8=0x278, 两者跳到同一个重试块 T), 必须恰好 1 对
  3. 把第一条 cbz 换成 b T

用法:
  python3 patch_qcodec2_alloc_retry.py <libqcodec2_v4l2codec.so 输入> <输出>
  python3 patch_qcodec2_alloc_retry.py --check <so>
依赖: pyelftools
"""
import sys, struct, hashlib
from elftools.elf.elffile import ELFFile

SYM = "_ZN3qc214QC2V4l2Decoder22DecoderOutputAllocator28handleOutputBufferAllocationENSt3__110shared_ptrINS_5EventEEE"


def die(msg):
    print("ERROR:", msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    data = bytearray(open(path, "rb").read())
    with open(path, "rb") as f:
        elf = ELFFile(f)
        if elf["e_machine"] != "EM_AARCH64":
            die(f"{path} 不是 arm64 ELF")
        sym = None
        for s in elf.get_section_by_name(".dynsym").iter_symbols():
            if s.name == SYM and s["st_value"]:
                sym = (s["st_value"], s["st_size"])
        segs = [(p["p_vaddr"], p["p_offset"], p["p_filesz"])
                for p in elf.iter_segments() if p["p_type"] == "PT_LOAD"]
    if not sym:
        die("找不到 handleOutputBufferAllocation 符号(不是高通 V4L2 Codec2 vendor 库?)")
    va = sym[0]
    for vaddr, off, sz in segs:
        if vaddr <= va < vaddr + sz:
            foff = va - vaddr + off
            break
    else:
        die("符号不在 PT_LOAD 里")
    insns = [(va + i, foff + i, struct.unpack_from("<I", data, foff + i)[0])
             for i in range(0, sym[1], 4)]
    return data, insns


def is_ldr_x_uoff(i):
    return (i & 0xFFC00000) == 0xF9400000


def ldr_off(i):
    return ((i >> 10) & 0xFFF) * 8


def is_cbz_x(i):
    return (i & 0xFF000000) == 0xB4000000


def is_b(i):
    return (i & 0xFC000000) == 0x14000000


def br_target(pc, i):
    if is_cbz_x(i):
        imm = (i >> 5) & 0x7FFFF
        if imm & 0x40000:
            imm -= 0x80000
        return pc + imm * 4
    imm = i & 0x3FFFFFF
    if imm & 0x2000000:
        imm -= 0x4000000
    return pc + imm * 4


def find(insns):
    """返回 [(状态, va, foff, insn, target)]"""
    pairs = []      # (K, va, foff, insn, target, kind)
    for k in range(len(insns) - 1):
        _, _, a = insns[k]
        va, fo, b = insns[k + 1]
        if not is_ldr_x_uoff(a):
            continue
        rt = a & 0x1F
        if is_cbz_x(b) and (b & 0x1F) == rt:
            pairs.append((ldr_off(a), va, fo, b, br_target(va, b), "cbz"))
        elif is_b(b):
            pairs.append((ldr_off(a), va, fo, b, br_target(va, b), "b"))
    hits = []
    for K, va, fo, ins, tgt, kind in pairs:
        for K2, _, _, _, tgt2, kind2 in pairs:
            if kind2 == "cbz" and K2 == K - 8 and tgt2 == tgt:
                hits.append((kind, va, fo, ins, tgt, K))
                break
    return hits


def enc_b(pc, target):
    return 0x14000000 | (((target - pc) // 4) & 0x3FFFFFF)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        _, insns = load(sys.argv[2])
        hits = find(insns)
        if len(hits) != 1:
            print(f"异常/不支持: 命中 {len(hits)} 处")
            return
        kind, va, fo, ins, tgt, K = hits[0]
        if kind == "cbz":
            print(f"未打补丁: 文件偏移 {fo:#x} cbz (阈值字段 {K:#x}) -> {tgt:#x}; 超时 >阈值后会放弃分配")
        else:
            print(f"已打补丁: 文件偏移 {fo:#x} 为无条件 b {tgt:#x}")
        return
    if len(sys.argv) != 3:
        die(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    data, insns = load(src)
    hits = find(insns)
    if len(hits) != 1:
        die(f"命中 {len(hits)} 处, 预期 1 处, 中止")
    kind, va, fo, ins, tgt, K = hits[0]
    if kind != "cbz":
        die("已经打过补丁了")
    new = enc_b(va, tgt)
    struct.pack_into("<I", data, fo, new)
    open(dst, "wb").write(data)
    print(f"阈值字段 {K:#x}; 文件偏移 {fo:#x}: {ins:08x} (cbz) -> {new:08x} (b {tgt:#x})")
    print("sha256 in :", hashlib.sha256(open(src, "rb").read()).hexdigest())
    print("sha256 out:", hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
