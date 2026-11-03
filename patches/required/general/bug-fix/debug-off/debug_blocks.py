#!/usr/bin/env python3
"""删 Mystic 加在 build.prop 里的调试段。用法: debug_blocks.py <build.prop>

  - '# Force ADB' 段:注释、下面连续的 persist.sys.usb.config / ro.adb.secure / ro.secure / ro.debuggable 行、紧跟的一个空行
  - '# Logcat' 段:只删注释和 logd.logpersistd* 行(后面可能直接接着别的属性)
没有这些段(别的 GSI)就什么也不改。
"""
import sys


ADB_KEYS = {"persist.sys.usb.config", "ro.adb.secure", "ro.secure", "ro.debuggable"}


def drop(lines):
    out, mode, n = [], None, 0
    for l in lines:
        s = l.strip()
        if s == "# Force ADB":
            mode = "adb"; n += 1; continue
        if s == "# Logcat":
            mode = "logcat"; n += 1; continue
        if mode == "adb":
            # 只吞这个段里已知的几个调试属性,不吞后面紧跟的别的行
            # (别的模块可能刚在文件末尾追加了属性,不能误删)
            if s.split("=", 1)[0] in ADB_KEYS:
                continue
            mode = None
            if not s:
                continue
        if mode == "logcat":
            if s.startswith("logd.logpersistd"):
                continue
            mode = None
        out.append(l)
    return out, n


if __name__ == "__main__":
    path = sys.argv[1]
    lines = open(path, encoding="utf-8").read().splitlines()
    out, n = drop(lines)
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"debug_blocks: 找到 {n} 个调试段", file=sys.stderr)
