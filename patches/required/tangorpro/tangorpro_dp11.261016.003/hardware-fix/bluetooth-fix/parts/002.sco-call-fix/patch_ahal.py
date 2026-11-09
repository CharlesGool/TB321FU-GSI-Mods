#!/usr/bin/env python3
"""给原厂 audio.primary.pineapple.so 去掉"开 SCO 前必须先挂起 A2DP"的 4 处检查。

背景: A2DP 改走 bluetooth_qti 软件编码后, PAL 里的 A2DP 设备从来不会"连上",
AHAL 下发 A2dpSuspended=true 时 PAL 返回 -22, 但 pal_get_param(PAL_PARAM_ID_BT_A2DP_SUSPENDED)
仍然成功并返回 a2dp_suspended=0。AHAL 在下面 4 处看到"未挂起"就拒绝打开/切换到 SCO,
表现是蓝牙通话一开始双方都听不见, 或者麦克风回落到平板内置麦克风。

4 处都是同一结构(AArch64):
    mov  w0, #0x10            ; PAL_PARAM_ID_BT_A2DP_SUSPENDED   52800200
    mov  x3, xzr
    bl   pal_get_param
    cbnz w0, ok               ;                                  350000e0
    ... (几条 ldr / cbz x8 取结构体)
    ldrb w8, [x8, #5]         ; a2dp_suspended                   39401508
    cbz  w8, <ERR "... if A2dp is not suspended">                34xxxx08
把最后这条 cbz w8 换成 nop, 其余逻辑不变。

定位不靠写死的偏移, 按上面的指令特征扫 .text: 一条 cbz w8 紧接在 ldrb w8,[x8,#5] 之后,
往前 12 条指令内有 mov w0,#0x10, 并且两者之间有 cbnz w0。换 vendor 后偏移变了也能找到。
找到的个数必须正好是 EXPECT(4); 不是就拒绝并列出找到的位置, 去反汇编确认(报 "A2dp is not suspended" 的分支)
再决定改 EXPECT 还是改特征。

用法: patch_ahal.py <原厂 so> <输出 so>
"""
import hashlib
import struct
import sys

NOP = 0xD503201F
MOV_W0_0X10 = 0x52800200
CBNZ_W0 = 0x350000E0
LDRB_W8_X8_5 = 0x39401508
EXPECT = 4
WINDOW = 12  # cbz 往前最多看几条指令找 mov w0,#0x10
# 已核对过的原厂库(sha256 -> (说明, 4 处 cbz 的文件偏移))。不在表里也会按特征找。
KNOWN = {
    "d8fcef36f25590b2758460b810178af25c5bd8dfa08c1e9aee0109d9217d5be3":
        ("ZUI 17.0.12.044 (A15 ROW, 9008FACTORY_CRACKED)", [0x547C4, 0x58F24, 0x5EB98, 0x613B8]),
    "f468566521d97efb7309ba89c23104bd22a1853eca744f99cb4d368a40d454af":
        ("ZUI 17.5.10.170", [0x547C4, 0x58F24, 0x5EB98, 0x613B8]),
}


def find_sites(d):
    """返回所有符合特征的 cbz w8 的文件偏移(.text 的虚拟地址和文件偏移一致)。"""
    n = len(d) // 4
    w = struct.unpack_from("<%dI" % n, d, 0)
    out = []
    for i in range(WINDOW + 1, n):
        if w[i] & 0xFF00001F != 0x34000008 or w[i - 1] != LDRB_W8_X8_5:
            continue
        back = w[i - WINDOW - 1:i]
        if MOV_W0_0X10 in back and CBNZ_W0 in back[back.index(MOV_W0_0X10):]:
            out.append(i * 4)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    d = bytearray(open(src, "rb").read())
    sha = hashlib.sha256(d).hexdigest()
    known = KNOWN.get(sha)
    print(f"原厂库 sha256 {sha}({known[0] if known else '没核对过的版本, 按指令特征查找'})")
    sites = find_sites(d)
    if len(sites) != EXPECT:
        sys.exit(f"按特征找到 {len(sites)} 处({' '.join(hex(s) for s in sites) or '没有'}), 预期 {EXPECT} 处。"
                 f"vendor 换了版本: 反汇编确认哪些是报 \"A2dp is not suspended\" 的分支, 再改 EXPECT 或特征")
    if known and sites != known[1]:
        sys.exit(f"这份库是已核对过的版本, 但找到的位置 {[hex(s) for s in sites]} 和记录的 {[hex(s) for s in known[1]]} 不一致")
    for off in sites:
        d[off:off + 4] = struct.pack("<I", NOP)
        print(f"  {off:#x}: cbz w8 -> nop")
    open(dst, "wb").write(d)
    print(f"写出 {dst} sha256 {hashlib.sha256(d).hexdigest()}")


if __name__ == "__main__":
    main()
