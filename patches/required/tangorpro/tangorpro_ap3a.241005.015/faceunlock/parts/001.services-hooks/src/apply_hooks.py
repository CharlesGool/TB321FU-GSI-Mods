#!/usr/bin/env python3
"""给 apktool 反编译出来的 services.jar 打 Sense 入口。

用法: apply_hooks.py <apktool 反编译根目录(里面有 smali/)>

打三类入口, 都幂等(改过的文件不会再次改):
1. 原 KLC/Sense 入口(2026-10-27 v1 起就有的, 不动语义):
   AuthService.registerFaceSensors: 走 SenseHooks.canUseProvider() 当兜底
   FaceService$FaceServiceWrapper.getProviders: 先走 SenseHooks.getProviders(service),
       返回非空就直接 return, null 走原逻辑; 原文件末尾的 canUseProvider() 兜底
2. AIDL @EnforcePermission 的放行(2026-10-27 v3 新加):
   FaceService$FaceServiceWrapper / BiometricService$BiometricServiceWrapper / AuthService$AuthServiceImpl
   里每个 `invoke-super {p0}, L.../I...Service$Stub;->foo_enforcePermission()V` 换成
   `invoke-static {}, SenseHooks;->enforceInternal()V`。底包 USE_BIOMETRIC_INTERNAL 是 signature(无 privileged),
   自签名的 ParanoidSense 拿不到, 走 SenseHooks 按 com.android.faceunlock 系统 priv-app 身份放行
3. 剩下的几处直接 USE_BIOMETRIC_INTERNAL 校验:
   FaceService$FaceServiceWrapper.addAuthenticatorsRegisteredCallback 用 Utils.checkPermission,
   AuthService.checkInternalPermission / AuthService$AuthServiceImpl.setActiveUser 用 Context.enforceCallingOrSelfPermission,
   FingerprintService$1.getSensorPropertiesInternal 用 Context.checkCallingOrSelfPermission,
   Utils.hasInternalPermission(Context) 返回 bool, 都走 SenseHooks(enforceInternal 或 hasInternal)

幂等靠的是: 每个 patch 都先 grep 新调用, 已经有就跳过。
"""
import os
import re
import sys

HOOK_CLS = "Lcom/android/server/biometrics/sensors/face/sense/SenseHooks;"
ENFORCE = "invoke-static {}, " + HOOK_CLS + "->enforceInternal()V"
CANUSE = "invoke-static {}, " + HOOK_CLS + "->canUseProvider()Z"
GETPROVIDERS = "invoke-static {v0}, " + HOOK_CLS + "->getProviders(Lcom/android/server/biometrics/sensors/face/FaceService;)Ljava/util/List;"
HAS_INTERNAL = "invoke-static {p0}, " + HOOK_CLS + "->hasInternal(Landroid/content/Context;)Z"


def read(p):
    return open(p, encoding="utf-8").read()


def write(p, s):
    open(p, "w", encoding="utf-8").write(s)


def once(name, condition, action):
    """action 返回 True 表示打了; condition 是幂等检查."""
    if condition():
        print(f"  skip (already applied): {name}")
        return False
    r = action()
    print(f"  {'ok' if r else 'FAIL'}: {name}")
    return r


def patch_enforce_bypass(path):
    """把文件里每个 _enforcePermission()V invoke-super 替换成 enforceInternal()V 的 invoke-static。"""
    if not os.path.exists(path):
        return 0
    s = read(path)
    pat = re.compile(
        r"^(\s*)invoke-super \{p0\}, L[^;]+/I[^;]+Service\$Stub;->\w+_enforcePermission\(\)V\s*$",
        re.M,
    )
    hits = pat.findall(s)
    if not hits:
        return 0
    s2 = pat.sub(lambda m: m.group(1) + ENFORCE, s)
    write(path, s2)
    return len(hits)


def patch_face_wrapper_authreg_callback(path):
    """FaceService$FaceServiceWrapper.addAuthenticatorsRegisteredCallback: Utils.checkPermission(ctx, USE_BIOMETRIC_INTERNAL)
    已经被 _enforcePermission 的 pass 覆盖掉了吗? 不是, 这个方法没有 _enforcePermission。它直接 Utils.checkPermission。
    这里改: 把那一段换成一个 SenseHooks.enforceInternal() 调用。
    保留原来 iget this$0 和 getContext, 只删掉 const-string 和 Utils.checkPermission 两行。
    改为直接 invoke-static enforceInternal(), 不依赖寄存器。"""
    s = read(path)
    pat = re.compile(
        r'(\s+iget-object v(\d+), p0, L[^;]+/FaceService\$FaceServiceWrapper;->this\$0:[^\n]*\n'
        r'\s*\n\s*invoke-virtual \{v\2\}, Lcom/android/server/SystemService;->getContext\(\)Landroid/content/Context;\s*\n'
        r'\s*\n\s*move-result-object v\2\s*\n'
        r'\s*\n\s*const-string v\d+, "android\.permission\.USE_BIOMETRIC_INTERNAL"\s*\n'
        r'\s*\n\s*invoke-static \{v\2, v\d+\}, Lcom/android/server/biometrics/Utils;->checkPermission\(Landroid/content/Context;Ljava/lang/String;\)V)'
    )
    m = pat.search(s)
    if not m:
        return False
    s2 = s[: m.start()] + "\n    " + ENFORCE + s[m.end():]
    write(path, s2)
    return True


def patch_utils_check(path, perm="android.permission.USE_BIOMETRIC_INTERNAL"):
    """删 const-string(perm) + Utils->checkPermission(Context;Str;)V 调用链, 换成 enforceInternal。"""
    s = read(path)
    pat = re.compile(
        r'(\s+)const-string v\d+, "' + re.escape(perm) + r'"\s*\n'
        r'\s*\n\s*invoke-static \{v\d+, v\d+\}, Lcom/android/server/biometrics/Utils;->checkPermission\(Landroid/content/Context;Ljava/lang/String;\)V'
    )
    s2, n = pat.subn(lambda m: m.group(1) + ENFORCE, s)
    if n:
        write(path, s2)
    return n


def patch_direct_enforce(path, perm="android.permission.USE_BIOMETRIC_INTERNAL"):
    """删掉 Context.enforceCallingOrSelfPermission(perm, msg)/checkCallingOrSelfPermission(perm) 的调用链, 换成 enforceInternal()。
    匹配一段连续的: 可选 move-result-object + const-string(perm) + 可选 const-string(msg) + invoke-virtual enforce/check。"""
    s = read(path)
    # enforceCallingOrSelfPermission(perm, msg) 版本
    pat1 = re.compile(
        r'(\s+)const-string v\d+, "' + re.escape(perm) + r'"\s*\n'
        r'(\s*\n\s*const-string v\d+, [^\n]+\n)?'
        r'\s*\n\s*invoke-virtual \{p?\w+, v\d+(, v\d+)?\}, Landroid/content/Context;->enforceCallingOrSelfPermission\(Ljava/lang/String;(Ljava/lang/String;)?\)V'
    )
    s2, n1 = pat1.subn(lambda m: m.group(1) + ENFORCE, s)

    # checkCallingOrSelfPermission(perm)->I 后面 if-eqz/if-nez 判定: 不改语义, 整段换成 "调 hasInternal, 结果取反为 int (0=granted)"
    # 这个在 FingerprintService$1.getSensorPropertiesInternal 用来做 "if 没 USE_BIOMETRIC_INTERNAL 就检查 TEST_BIOMETRIC" 的分支。
    # 整个意思是 "需要 USE_BIOMETRIC_INTERNAL 或 TEST_BIOMETRIC"; 放行后相当于只要有 USE_BIOMETRIC_INTERNAL/MANAGE_BIOMETRIC 就跳过 TEST_BIOMETRIC 的检查, 没问题。
    pat2 = re.compile(
        r'(\s+)const-string v(\d+), "' + re.escape(perm) + r'"\s*\n'
        r'\s*\n\s*invoke-virtual \{(\w+), v\2\}, Landroid/content/Context;->checkCallingOrSelfPermission\(Ljava/lang/String;\)I\s*\n'
        r'\s*\n\s*move-result (\w+)'
    )
    # 这里改成 call hasInternal(ctx) 然后反转: res = 0 if hasInternal else 1 (匹配 checkCallingOrSelfPermission 的语义: 0=granted)
    def rep2(m):
        ind = m.group(1)
        reg = m.group(2)
        ctx = m.group(3)
        dst = m.group(4)
        # 为了不打乱寄存器, 用 move-object 到 p0; 但原方法可能 p0 已占。更稳妥: 直接取反, 用 if-nez.
        # smali 里 bool->int: hasInternal 返 Z, 返回 0 或 1. 我们要: granted(1)->0, denied(0)->1.
        return (
            ind + "invoke-static {" + ctx + "}, " + HOOK_CLS + "->hasInternal(Landroid/content/Context;)Z\n"
            + ind + "\n" + ind + "move-result " + dst + "\n"
            + ind + "\n" + ind + "xor-int/lit8 " + dst + ", " + dst + ", 0x1"
        )
    s3, n2 = pat2.subn(rep2, s2)
    if n1 + n2 == 0:
        return 0
    write(path, s3)
    return n1 + n2


def patch_has_internal_permission(path):
    """Utils.hasInternalPermission(Context): 把方法体换成 return SenseHooks.hasInternal(p0)。"""
    s = read(path)
    pat = re.compile(
        r'(\.method public static hasInternalPermission\(Landroid/content/Context;\)Z\n)'
        r'(\s*\.locals \d+\s*\n)'
        r'(.*?)'
        r'(\.end method)',
        re.S,
    )
    m = pat.search(s)
    if not m:
        return False
    if HOOK_CLS + "->hasInternal" in m.group(3):
        return False
    body = (
        "    .locals 1\n\n"
        "    " + HAS_INTERNAL + "\n\n"
        "    move-result p0\n\n"
        "    return p0\n"
    )
    s2 = s[: m.start()] + m.group(1) + body + m.group(4) + s[m.end():]
    write(path, s2)
    return True


def patch_original_hooks(root):
    """原来的 3 处 hook, 和 v1 的 smali-hooks.patch 一致。"""
    changed = False

    # AuthService.registerFaceSensors 入口
    p = os.path.join(root, "smali/com/android/server/biometrics/AuthService.smali")
    s = read(p)
    if "SenseHooks;->canUseProvider" not in s:
        marker = '    const-string p0, "AuthService"\n\n    const-string p1, "No face sensors."'
        rep = ("    " + CANUSE + "\n\n    move-result v0\n\n    if-nez v0, :cond_1\n\n" + marker)
        if marker in s:
            s = s.replace(marker, rep, 1)
            write(p, s)
            print("  ok: AuthService.registerFaceSensors")
            changed = True
        else:
            print("  FAIL: AuthService marker not found")
    else:
        print("  skip (already applied): AuthService.registerFaceSensors")

    # FaceService$FaceServiceWrapper.getProviders(service): 先走 SenseHooks
    p = os.path.join(root, "smali/com/android/server/biometrics/sensors/face/FaceService$FaceServiceWrapper.smali")
    s = read(p)
    getp_pat = re.compile(
        r"(\.method public final getProviders\(Landroid/hardware/face/FaceSensorConfigurations;\)Ljava/util/List;\s*\n"
        r"\s*\.locals \d+\s*\n)"
    )
    if "SenseHooks;->getProviders" not in s:
        m = getp_pat.search(s)
        if m:
            hook_block = (
                "    iget-object v0, p0, Lcom/android/server/biometrics/sensors/face/FaceService$FaceServiceWrapper;->this$0:Lcom/android/server/biometrics/sensors/face/FaceService;\n\n"
                "    " + GETPROVIDERS + "\n\n"
                "    move-result-object v0\n\n"
                "    if-eqz v0, :sense_fallthrough\n\n"
                "    return-object v0\n\n"
                "    :sense_fallthrough\n"
            )
            s = s[: m.end()] + hook_block + s[m.end():]
            write(p, s)
            print("  ok: FaceServiceWrapper.getProviders (Sense first)")
            changed = True
        else:
            print("  FAIL: getProviders method not found")
    else:
        print("  skip (already applied): FaceServiceWrapper.getProviders")

    # FaceService$FaceServiceWrapper.registerAuthenticators 的 canUseProvider 兜底
    s = read(p)  # 重读, 上一步可能改了
    reg_pat = re.compile(
        r"\.method public registerAuthenticators\(Landroid/hardware/face/FaceSensorConfigurations;\)V[\s\S]+?\.end method"
    )
    m = reg_pat.search(s)
    if m and "SenseHooks;->canUseProvider" not in m.group(0):
        body = m.group(0)
        # 在方法内首个 "move-result v0 \n\n <indent> if-nez v0, :cond_0" 处, 把那段换成:
        #   move-result v0 \n\n <indent> if-nez v0, :cond_0 \n\n <indent> <canUseProvider()> \n\n <indent> move-result v0 \n\n <indent> if-nez v0, :cond_0
        chunk_pat = re.compile(r"move-result v0\n\n(    )if-nez v0, :cond_0")
        def inject(mm):
            ind = mm.group(1)
            return ("move-result v0\n\n" + ind + "if-nez v0, :cond_0\n\n"
                    + ind + CANUSE + "\n\n"
                    + ind + "move-result v0\n\n"
                    + ind + "if-nez v0, :cond_0")
        body2, n = chunk_pat.subn(inject, body, count=1)
        if n:
            s2 = s[:m.start()] + body2 + s[m.end():]
            write(p, s2)
            print("  ok: FaceServiceWrapper.registerAuthenticators (canUseProvider fallback)")
            changed = True
        else:
            print("  FAIL: registerAuthenticators pattern not found inside method")
    else:
        print("  skip (already applied): FaceServiceWrapper.registerAuthenticators")

    return changed


def main():
    root = sys.argv[1]
    smali = os.path.join(root, "smali")
    if not os.path.isdir(smali):
        sys.exit(f"{smali}: no smali dir")
    print("=== 1. 原 Sense 入口")
    patch_original_hooks(root)

    print("=== 2. @EnforcePermission 放行")
    for rel in (
        "smali/com/android/server/biometrics/sensors/face/FaceService$FaceServiceWrapper.smali",
        "smali/com/android/server/biometrics/BiometricService$BiometricServiceWrapper.smali",
        "smali/com/android/server/biometrics/AuthService$AuthServiceImpl.smali",
    ):
        p = os.path.join(root, rel)
        n = patch_enforce_bypass(p)
        print(f"  {rel}: {n} 处 _enforcePermission -> SenseHooks.enforceInternal")

    print("=== 3. 直接 USE_BIOMETRIC_INTERNAL 校验")
    p = os.path.join(root, "smali/com/android/server/biometrics/sensors/face/FaceService$FaceServiceWrapper.smali")
    once("FaceServiceWrapper.addAuthenticatorsRegisteredCallback (Utils.checkPermission)",
         lambda: "addAuthenticatorsRegisteredCallback" in read(p) and read(p).count(f'const-string v1, "android.permission.USE_BIOMETRIC_INTERNAL"') == 0,
         lambda: patch_face_wrapper_authreg_callback(p))

    for rel in ("smali/com/android/server/biometrics/AuthService.smali",
                "smali/com/android/server/biometrics/AuthService$AuthServiceImpl.smali"):
        p = os.path.join(root, rel)
        n = patch_direct_enforce(p)
        print(f"  {rel}: {n} 处 Context.enforce(USE_BIOMETRIC_INTERNAL)")

    p = os.path.join(root, "smali/com/android/server/biometrics/sensors/fingerprint/FingerprintService$1.smali")
    n1 = patch_direct_enforce(p)
    n2 = patch_utils_check(p)
    print(f"  FingerprintService$1: {n1} 处 Context.check + {n2} 处 Utils.checkPermission")

    p = os.path.join(root, "smali/com/android/server/biometrics/Utils.smali")
    r = patch_has_internal_permission(p)
    print(f"  Utils.hasInternalPermission -> SenseHooks.hasInternal: {'ok' if r else 'skip'}")

    # 最后再扫一遍确认没剩
    leftover = []
    for dp, _, fs in os.walk(smali):
        for f in fs:
            if not f.endswith(".smali"):
                continue
            fp = os.path.join(dp, f)
            s = read(fp)
            if 'USE_BIOMETRIC_INTERNAL' in s:
                for i, ln in enumerate(s.splitlines(), 1):
                    if 'USE_BIOMETRIC_INTERNAL' in ln:
                        leftover.append(f"{os.path.relpath(fp, smali)}:{i}  {ln.strip()[:120]}")
    print(f"=== 剩余 USE_BIOMETRIC_INTERNAL 字符串出现 {len(leftover)} 处(字符串字面值或注解里的, 不是调用点就 OK):")
    for x in leftover[:40]:
        print("  " + x)


if __name__ == "__main__":
    main()
