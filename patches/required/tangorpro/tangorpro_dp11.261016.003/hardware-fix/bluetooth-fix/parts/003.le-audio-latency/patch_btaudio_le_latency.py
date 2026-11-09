#!/usr/bin/env python3
"""
TB321FU: 修复 vendor btaudio_offload_if.so 中 LE Audio 延迟单位错误(µs 当 ms)。

audio_get_a2dp_sink_latency(session):
  - A2DP 会话: GetPresentationPosition().remoteDeviceAudioDelayNanos / 1e6  -> 毫秒 (正确)
  - LE 会话 (AIDL SessionType 6 = LE_AUDIO_HW_OFFLOAD_ENCODING, 7 = ..._DECODING):
      直接取 LeAudioConfiguration.peerDelayUs (微秒) 存成 uint16 返回 -> PAL BtA2dp::getLatency 当毫秒用
      例: peerDelayUs=124000 -> &0xffff=58464 -> 上报 58.5 秒延迟; VoIP 应用按播放位置节流, 实际积压 ~60 秒
修复: 两个 LE 分支取到 peerDelayUs 后 /1000 再存。

原代码(两段, 每段 8 条):
  mov  wA,#0x1e0 ; umaddl xA,wB,wA,xC ; ldr wD,[xA,#cfgTag] ; cmp wD,#2 ; b.ne ASSERT
  add  xA,xA,#cfgOff ; ldr wA,[xA,#0x20] ; b STORE
其中前两条是冗余的(进入分支前 xA 已是同一个 entry 地址)。改为:
  段6: ldr wD,[xA,#tag6] ; cmp wD,#2 ; b.ne ASSERT ; ldr wA,[xA,#off6+0x20] ; b 段7.tail ; nop ; nop ; nop
  段7: ldr wD,[xA,#tag7] ; cmp wD,#2 ; b.ne ASSERT ; ldr wA,[xA,#off7+0x20]
       tail: mov wD,#1000 ; udiv wA,wA,wD ; b STORE ; nop
用法: patch_btaudio_le_latency.py [--check] <btaudio_offload_if.so> [输出]
"""
import sys, struct, hashlib
import capstone
from elftools.elf.elffile import ELFFile

NOP = 0xD503201F

def enc_ldr_w(rt, rn, off):
    assert off % 4 == 0 and 0 <= off // 4 < 4096
    return 0xB9400000 | ((off // 4) << 10) | (rn << 5) | rt

def enc_cmp_w_imm(rn, imm):
    return 0x7100001F | (imm << 10) | (rn << 5)

def enc_bcond(pc, target, cond):
    d = (target - pc) // 4
    assert -(1 << 18) <= d < (1 << 18)
    return 0x54000000 | ((d & 0x7FFFF) << 5) | cond

def enc_b(pc, target):
    d = (target - pc) // 4
    return 0x14000000 | (d & 0x3FFFFFF)

def enc_movz_w(rd, imm):
    return 0x52800000 | (imm << 5) | rd

def enc_udiv_w(rd, rn, rm):
    return 0x1AC00800 | (rm << 16) | (rn << 5) | rd

def reg(op):  # capstone operand -> register number (w/x)
    return None

def main():
    args = sys.argv[1:]
    check = False
    if args and args[0] == '--check':
        check = True; args = args[1:]
    if not args:
        print(__doc__); sys.exit(1)
    src = args[0]
    data = bytearray(open(src, 'rb').read())
    elf = ELFFile(open(src, 'rb'))
    text = elf.get_section_by_name('.text')
    tbase, toff = text['sh_addr'], text['sh_offset']
    code = bytes(data[toff:toff + text['sh_size']])
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    md.detail = True
    insns = list(md.disasm(code, tbase))
    idx = {i.address: k for k, i in enumerate(insns)}

    def mn(i):  # capstone 4 打 movz, capstone 5 打别名 mov;统一成 mov
        return 'mov' if i.mnemonic == 'movz' else i.mnemonic

    def R(i, n):  # register number of operand n
        name = i.reg_name(i.operands[n].reg)
        return 31 if name in ('wzr', 'xzr') else int(name[1:])

    def is_block(k):
        """原始 8 条结构, 返回 (A,B,C,D,tag,off,assert_t,store_t) 或 None"""
        s = insns[k:k + 8]
        if len(s) < 8: return None
        m = [mn(x) for x in s]
        if m != ['mov', 'umaddl', 'ldr', 'cmp', 'b.ne', 'add', 'ldr', 'b']: return None
        if s[0].op_str.split(',')[1].strip() != '#0x1e0': return None
        A = R(s[0], 0)
        if R(s[1], 0) != A or R(s[1], 2) != A: return None
        D = R(s[2], 0)
        if s[2].operands[1].mem.base == 0 or R(s[3], 0) != D or s[3].operands[1].imm != 2: return None
        tag = s[2].operands[1].mem.disp
        if R(s[5], 0) != A or R(s[5], 1) != A: return None
        off = s[5].operands[2].imm
        if R(s[6], 0) != A or s[6].operands[1].mem.disp != 0x20: return None
        return dict(A=A, B=R(s[1], 1), C=R(s[1], 3), D=D, tag=tag, off=off,
                    assert_t=s[4].operands[0].imm, store_t=s[7].operands[0].imm, addr=s[0].address)

    def is_patched(k):
        s = insns[k:k + 16]
        if len(s) < 16: return False
        m = [mn(x) for x in s]
        return (m[:8] == ['ldr', 'cmp', 'b.ne', 'ldr', 'b', 'nop', 'nop', 'nop'] and
                m[8:15] == ['ldr', 'cmp', 'b.ne', 'ldr', 'mov', 'udiv', 'b'] and
                s[12].op_str.endswith('#0x3e8'))

    hits, patched = [], []
    for k in range(len(insns) - 16):
        b6 = is_block(k)
        if b6:
            b7 = is_block(k + 8)
            if (b7 and b7['A'] == b6['A'] and b7['assert_t'] == b6['assert_t']
                    and b7['store_t'] == b6['store_t'] and b6['tag'] != b7['tag']):
                # 前置: dispatch 里 entry 地址已在 xA (umaddl xA ; ldrb wD,[xA,#..] ; cmp ; b.eq 段7 ; cmp ; b.ne ..)
                pre = insns[k - 6:k]
                pm = [x.mnemonic for x in pre]
                if (pm == ['umaddl', 'ldrb', 'cmp', 'b.eq', 'cmp', 'b.ne'] and R(pre[0], 0) == b6['A']
                        and pre[3].operands[0].imm == b7['addr'] and pre[4].operands[1].imm == 6
                        and pre[2].operands[1].imm == 7):
                    hits.append((b6, b7))
        if is_patched(k):
            patched.append(insns[k].address)

    sha = hashlib.sha256(data).hexdigest()
    print(f'{src}: sha256 {sha}')
    if patched and not hits:
        print(f'已打补丁 @ {[hex(a) for a in patched]}'); sys.exit(0 if check else 2)
    if len(hits) != 1:
        print(f'未命中或不唯一: {len(hits)} 处, 中止'); sys.exit(3)
    b6, b7 = hits[0]
    print(f'未打补丁: 段6 @ {b6["addr"]:#x} (tag {b6["tag"]:#x}, cfg {b6["off"]:#x}), '
          f'段7 @ {b7["addr"]:#x} (tag {b7["tag"]:#x}, cfg {b7["off"]:#x}), store {b6["store_t"]:#x}')
    if check:
        sys.exit(0)
    if len(args) < 2:
        print('缺少输出路径'); sys.exit(1)
    A, D = b6['A'], b6['D']
    p6, p7 = b6['addr'], b7['addr']
    tail = p7 + 16
    w = [
        enc_ldr_w(D, A, b6['tag']), enc_cmp_w_imm(D, 2), enc_bcond(p6 + 8, b6['assert_t'], 1),
        enc_ldr_w(A, A, b6['off'] + 0x20), enc_b(p6 + 16, tail), NOP, NOP, NOP,
        enc_ldr_w(D, A, b7['tag']), enc_cmp_w_imm(D, 2), enc_bcond(p7 + 8, b7['assert_t'], 1),
        enc_ldr_w(A, A, b7['off'] + 0x20),
        enc_movz_w(D, 1000), enc_udiv_w(A, A, D), enc_b(p7 + 24, b6['store_t']), NOP,
    ]
    fo = p6 - tbase + toff
    data[fo:fo + 64] = struct.pack('<16I', *w)
    for i in md.disasm(bytes(data[fo:fo + 64]), p6):
        print(f'  {i.address:#x}: {i.mnemonic} {i.op_str}')
    open(args[1], 'wb').write(data)
    print(f'写出 {args[1]}: sha256 {hashlib.sha256(data).hexdigest()}')

if __name__ == '__main__':
    main()
