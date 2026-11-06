#!/usr/bin/env python3
"""从 system_ext_seapp_contexts 里删掉引用 Pixel vendor 专属 SELinux 域的规则.

设备连接服务 com.google.android.apps.pixel.dcservice(.ui) 被指定到 dcservice_app 域, 这个类型来自 Pixel 的
vendor sepolicy, TB321FU 的 vendor 里没有 -> zygote setcontext 失败, 每 10 秒 SIGABRT 一次.
删掉这两行后它落到通用的 priv_app 域(isPrivApp=true 的默认规则).
原地改写文件(不新建), 保留属主/权限/SELinux 标签.

用法: fix_seapp.py <system_ext_seapp_contexts>
"""
import sys

DROP_DOMAINS = {"dcservice_app"}
EXPECT = 2

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)
keep, dropped = [], []
for line in lines:
    fields = dict(kv.split("=", 1) for kv in line.split() if "=" in kv)
    (dropped if fields.get("domain") in DROP_DOMAINS else keep).append(line)
if len(dropped) != EXPECT:
    sys.exit(f"expected to drop {EXPECT} lines, found {len(dropped)}")
with open(path, "r+", encoding="utf-8") as f:
    f.seek(0)
    f.write("".join(keep))
    f.truncate()
for line in dropped:
    print("  - " + line.strip())
