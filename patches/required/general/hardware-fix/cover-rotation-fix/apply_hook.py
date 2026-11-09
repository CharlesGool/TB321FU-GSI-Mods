#!/usr/bin/env python3
"""在 PhoneWindowManager.systemReady()V 最后一个 return-void 前插入
    Tb321fuHwPolicy.init(mContext, this)
用法: apply_hook.py <apktool 反编译的 services 目录>
输出 OK/FAIL 行;成功时最后一行是被改的 smali 相对路径。幂等:已经打过就报 FAIL(不该重复打)。"""
import os, re, sys

MARK = "Tb321fuHwPolicy;->init("
HOOK = [
    "    # TB321FU cover-rotation-fix: 霍尔皮套 + 触摸屏边缘防误触跟随旋转\n",
    "    iget-object v0, p0, Lcom/android/server/policy/PhoneWindowManager;->mContext:Landroid/content/Context;\n",
    "    invoke-static {v0, p0}, Lcom/android/server/policy/Tb321fuHwPolicy;->init(Landroid/content/Context;Ljava/lang/Object;)V\n",
]


def fail(msg):
    print("FAIL " + msg)
    sys.exit(1)


root = sys.argv[1]
hits = [d for d in sorted(os.listdir(root)) if d.startswith("smali")
        and os.path.isfile(os.path.join(root, d, "com/android/server/policy/PhoneWindowManager.smali"))]
if len(hits) != 1:
    fail(f"PhoneWindowManager.smali 找到 {len(hits)} 份,预期 1 份")
rel = os.path.join(hits[0], "com/android/server/policy/PhoneWindowManager.smali")
p = os.path.join(root, rel)
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
if any(MARK in l for l in lines):
    fail("PhoneWindowManager 已经打过钩子")
if not any(re.match(r"\.field [^\n]*\bmContext:Landroid/content/Context;", l) for l in lines):
    fail("PhoneWindowManager 没有 mContext:Landroid/content/Context; 字段")
starts = [i for i, l in enumerate(lines) if re.match(r"\.method public (final )?systemReady\(\)V", l)]
if len(starts) != 1:
    fail(f"systemReady()V 找到 {len(starts)} 个,预期 1 个")
start = starts[0]
end = next(i for i in range(start, len(lines)) if lines[i].startswith(".end method"))
loc = next((i for i in range(start, end) if re.match(r"\s+\.(locals|registers) \d+", lines[i])), None)
if loc is None:
    fail("systemReady 里没有 .locals")
m = re.match(r"(\s+)\.(locals|registers) (\d+)", lines[loc])
if m.group(2) == "registers":
    fail(".registers 写法不处理(apktool 默认出 .locals)")
if int(m.group(3)) < 1:
    lines[loc] = f"{m.group(1)}.locals 1\n"
rets = [i for i in range(start, end) if lines[i].strip() == "return-void"]
if not rets:
    fail("systemReady 里没有 return-void")
ret = rets[-1]
lines[ret:ret] = HOOK
open(p, "w", encoding="utf-8").writelines(lines)
print(f"OK systemReady() 第 {ret + 1} 行前插入 Tb321fuHwPolicy.init(mContext, this)")
print(rel)
