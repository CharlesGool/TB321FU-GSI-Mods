#!/usr/bin/env python3
"""检查 dex 里会让 ART 在运行时抛 IncompatibleClassChangeError / IllegalAccessError / NoClassDefFoundError 的问题.

用法: APKTOOL=apktool.jar check_dex.py [--boot classes.jar ...] <classes.dex | x.apk | x.jar> ...
  - invoke-custom / invoke-polymorphic / method handle 残留(应该全被 d8 desugar 掉)
  - private 方法必须用 invoke-direct 且只能在本类里调; 非 private 实例方法不能用 invoke-direct
  - static/实例 调用方式、字段指令和声明一致; private 字段只能本类访问
  - 给了 --boot(class jar, 比如 dex2jar 转出来的 framework.jar)时: 引用的类必须在这些 dex 里或 boot 里,
    java/ javax/ dalvik/ libcore/ sun/ jdk/ org/json/ org/xml/ org/w3c/ android/ 下的(apex 里的 boot jar)不查
有问题时打印并以 1 退出.
"""
import os
import re
import subprocess
import sys
import tempfile
import zipfile

args = sys.argv[1:]
boot_jars, inputs = [], []
while args:
    a = args.pop(0)
    if a == "--boot":
        boot_jars.append(args.pop(0))
    else:
        inputs.append(a)
apktool = os.environ.get("APKTOOL")
if not apktool or not inputs:
    sys.exit(__doc__)

tmp = tempfile.mkdtemp()
dexes = []
for i, path in enumerate(inputs):
    if path.endswith(".dex"):
        dexes.append(open(path, "rb").read())
    else:
        z = zipfile.ZipFile(path)
        dexes += [z.read(n) for n in z.namelist() if re.fullmatch(r"classes\d*\.dex", n)]
smali_root = os.path.join(tmp, "out")
for i, data in enumerate(dexes):
    jar = os.path.join(tmp, f"{i}.jar")
    with zipfile.ZipFile(jar, "w") as z:
        z.writestr("classes.dex", data)
    subprocess.run(["java", "-jar", apktool, "d", "-f", "-r", "-o", os.path.join(smali_root, str(i)), jar],
                   check=True, stdout=subprocess.DEVNULL)

CLASS_RE = re.compile(r"^\.class (.*?)(L[^;]+;)$")
METHOD_RE = re.compile(r"^\.method (.*?)(\S+\(.*)$")
FIELD_RE = re.compile(r"^\.field (.*?)(\S+):(\S+?)(\s*=.*)?$")
INVOKE_RE = re.compile(r"^\s*(invoke-[a-z]+)(?:/range)? \{[^}]*\}, (L[^;]+;)->([^(]+\([^)]*\)\S+)")
FIELDOP_RE = re.compile(r"^\s*([is](?:get|put)[a-z-]*) [^,]+(?:, [^,]+)?, (L[^;]+;)->([^:]+):")
BAD_RE = re.compile(r"invoke-custom|invoke-polymorphic|const-method-handle|const-method-type")
TYPE_RE = re.compile(r"L[A-Za-z0-9_$/-]+;")
STR_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
BOOT_PREFIXES = ("java/", "javax/", "dalvik/", "libcore/", "sun/", "jdk/", "org/json/", "org/xml/",
                 "org/w3c/", "android/")

methods, fields, defined = {}, {}, set()
parsed = []
for root, _, files in os.walk(smali_root):
    for f in files:
        if not f.endswith(".smali"):
            continue
        path = os.path.join(root, f)
        lines = open(path, encoding="utf-8").read().splitlines()
        cls = CLASS_RE.match(lines[0]).group(2)
        defined.add(cls)
        for ln in lines:
            m = METHOD_RE.match(ln)
            if m:
                methods[(cls, m.group(2))] = m.group(1).split()
            m = FIELD_RE.match(ln)
            if m:
                fields[(cls, m.group(2))] = m.group(1).split()
        parsed.append((cls, path, lines))

boot = set()
for j in boot_jars:
    for n in zipfile.ZipFile(j).namelist():
        if n.endswith(".class"):
            boot.add("L" + n[:-6] + ";")

errors, missing = [], {}
for cls, path, lines in parsed:
    rel = os.path.relpath(path, smali_root)
    for no, ln in enumerate(lines, 1):
        where = f"{rel}:{no}: {ln.strip()[:160]}"
        if boot_jars and not ln.lstrip().startswith(("#", ".source", ".line")):
            # 引号里的是字符串(Kotlin metadata、泛型签名), 运行时不加载
            for t in TYPE_RE.findall(STR_RE.sub('""', ln)):
                if t not in defined and t not in boot and not t[1:].startswith(BOOT_PREFIXES):
                    missing.setdefault(t, where)
        if BAD_RE.search(ln):
            errors.append("not desugared: " + where)
            continue
        m = INVOKE_RE.match(ln)
        if m:
            op, owner, sig = m.groups()
            flags = methods.get((owner, sig))
            if flags is None:
                continue
            name = sig.split("(")[0]
            if "private" in flags and "static" not in flags and (op != "invoke-direct" or owner != cls):
                errors.append(f"{op} on private {owner}->{name}: " + where)
            elif "private" in flags and owner != cls:
                errors.append(f"cross-class call to private static {owner}->{name}: " + where)
            elif "static" in flags and op != "invoke-static":
                errors.append(f"{op} on static method: " + where)
            elif "static" not in flags and op == "invoke-static":
                errors.append("invoke-static on instance method: " + where)
            elif op == "invoke-direct" and "private" not in flags and name != "<init>":
                errors.append("invoke-direct on non-private method: " + where)
            continue
        m = FIELDOP_RE.match(ln)
        if m:
            op, owner, name = m.groups()
            flags = fields.get((owner, name))
            if flags is None:
                continue
            if "private" in flags and owner != cls:
                errors.append(f"cross-class access to private field {owner}->{name}: " + where)
            if ("static" in flags) != op.startswith("s"):
                errors.append(f"{op} static/instance mismatch: " + where)

for t, where in sorted(missing.items()):
    errors.append(f"class not in dex or boot: {t}  (first use {where})")
print(f"check_dex: {len(dexes)} dex, {len(parsed)} classes, {len(methods)} methods, {len(fields)} fields, "
      f"{len(errors)} problems")
for e in errors[:200]:
    print("  " + e)
sys.exit(1 if errors else 0)
