#!/usr/bin/env python3
"""把 android.os.Build.isBuildConsistent() 的 smali 方法体替换成直接 return true.

背景: GSI 的 framework(system)和联想 vendor 不是同一套编译产物, IS_TREBLE_ENABLED=true 时这个方法会调
VintfObject.verifyBuildAtBoot() 比较 framework compatibility matrix 和 vendor manifest(HAL/SELinux/kernel 版本等),
对不上就返回非 0。唯一调用方 ActivityTaskManagerService$LocalService 在非 eng 构建上会据此 post 一个 Runnable
弹出"设备内部出现了问题"对话框(见 smali: "Build fingerprint is not consistent, warning user")。
全系统 grep 过(见 V8.3 报告), 整个镜像只有 framework.jar 这一处实现、services.jar 这一处调用, 没有第二条路径。
这个方法只影响这条提示, 不是 AVB/dm-verity/SELinux 那层真校验, 也不参与 Play Integrity attestation。

用法: patch_build_consistent.py <apktool 反编译 framework.jar 得到的目录(含 smali_classesN/)>
"""
import re
import sys
from pathlib import Path

OLD_SIG = ".method public static greylist-max-o isBuildConsistent()Z"
NEW_BODY = (
    OLD_SIG + "\n"
    "    .locals 1\n\n"
    "    # TB321FU: 短路跳过 framework/vendor 一致性检查(GSI 场景下框架和联想 vendor 本来就不是一套编译产物,\n"
    "    # 不这样改开机会弹\"设备内部出现了问题\"), 不影响 AVB/dm-verity/SELinux 或 Play Integrity attestation。\n"
    "    const/4 v0, 0x1\n\n"
    "    return v0\n"
    ".end method"
)


def main():
    root = Path(sys.argv[1])
    hits = [p for p in root.rglob("Build.smali") if p.read_text(encoding="utf-8").count(OLD_SIG) == 1]
    if len(hits) != 1:
        sys.exit(f"期望找到 1 个含 isBuildConsistent 的 Build.smali, 找到 {len(hits)}: {hits}")
    path = hits[0]
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(re.escape(OLD_SIG) + r".*?\n\.end method", re.DOTALL)
    matches = pattern.findall(text)
    if len(matches) != 1:
        sys.exit(f"isBuildConsistent 方法块匹配到 {len(matches)} 处, 期望 1 处")
    new_text = pattern.sub(lambda _m: NEW_BODY, text, count=1)
    path.write_text(new_text, encoding="utf-8")
    print(f"  patch_build_consistent: {path.relative_to(root)} 的 isBuildConsistent() 改为直接 return true")


if __name__ == "__main__":
    main()
