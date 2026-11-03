#!/usr/bin/env python3
"""从原厂固件的 build.prop 现取指纹和 build 描述符,输出成 overlay.prop(stdout)。

用法: stock_overlay.py <原厂 system/build.prop> [原厂 vendor/build.prop] > overlay.prop
换固件后自动跟着变;原厂 build.prop 缺任何一个需要的 key 就报错退出。
"""
import sys


def load(p):
    return open(p, encoding="utf-8").read().splitlines()


def props(lines):
    d = {}
    for l in lines:
        if "=" in l and not l.lstrip().startswith("#"):
            k, v = l.split("=", 1)
            d.setdefault(k, v)
    return d


def main():
    stock_sys = sys.argv[1]
    stock_vendor = sys.argv[2] if len(sys.argv) > 2 else None
    s = props(load(stock_sys))
    fp = s.get("ro.build.fingerprint") or s.get("ro.system.build.fingerprint")
    if not fp:
        sys.exit("原厂 system/build.prop 里没有 fingerprint")
    out = ["# 由 patches/required/general/bug-fix/identity/parts/002.build-fingerprint/stock_overlay.py 从原厂固件生成,不要手改"]
    for part in ("", "system.", "product.", "vendor.", "odm.", "bootimage.", "system_ext."):
        out.append(f"ro.{part}build.fingerprint={fp}")
    keys = ["ro.build.id", "ro.system.build.id", "ro.build.version.security_patch",
            "ro.build.version.release", "ro.build.version.release_or_codename",
            "ro.build.version.incremental", "ro.build.tags", "ro.system.build.tags",
            "ro.build.type", "ro.build.flavor", "ro.build.description"]
    for k in keys:
        if k not in s:
            sys.exit(f"原厂 system/build.prop 里没有 {k}")
        out.append(f"{k}={s[k]}")
    vpatch = None
    if stock_vendor:
        vpatch = props(load(stock_vendor)).get("ro.vendor.build.security_patch")
    out.append(f"ro.vendor.build.security_patch={vpatch or s['ro.build.version.security_patch']}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
