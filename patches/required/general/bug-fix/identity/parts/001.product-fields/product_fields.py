#!/usr/bin/env python3
"""把一份 build.prop 里的机型字段改成目标机型。

用法: product_fields.py <system|product|system_ext> <build.prop>
环境变量: ID_BRAND ID_DEVICE ID_MANUFACTURER ID_MODEL ID_NAME GSI_CODENAME

- 三个分区都改 ro.product.<分区>.{brand,device,manufacturer,model,name};key 找不到就报错退出
  (底包变了、字段不见了,宁可构建失败)。
- system 另外改 ro.build.product,以及 ro.build.flavor / ro.build.description 开头的 "<GSI_CODENAME>-user"
  (开头不是 GSI 原机代号就不碰,所以和 build-fingerprint 谁先谁后都行)。
- product 另外改 ro.quick_start.device_id(Pixel 底包里才有;没有就跳过,不算错)。
"""
import os
import sys


def main():
    part, path = sys.argv[1], sys.argv[2]
    env = lambda k: os.environ[k]
    lines = open(path, encoding="utf-8").read().splitlines()

    def set_all(key, value, required=True):
        n = 0
        for i, l in enumerate(lines):
            if not l.lstrip().startswith("#") and l.split("=", 1)[0] == key:
                lines[i] = f"{key}={value}"
                n += 1
        if not n and required:
            sys.exit(f"product_fields: build.prop 里找不到 {key}")
        return n

    for f in ("brand", "device", "manufacturer", "model", "name"):
        set_all(f"ro.product.{part}.{f}", env(f"ID_{f.upper()}"))

    dev = env("ID_DEVICE")
    if part == "system":
        # ro.build.product 是旧别名,Android 17 起不再出现在 system/build.prop;有就改,没有就跳过。
        if not set_all("ro.build.product", dev, required=False):
            print("product_fields: system 里没有 ro.build.product(A17 起已移除),跳过", file=sys.stderr)
        # flavor / description 开头的 "<GSI_CODENAME>-user" 换成 "<ID_DEVICE>-user"。
        # 只在开头是 GSI 原机代号时才换:build-fingerprint 先跑过的话它们已经是原厂值,这里就不碰,
        # 所以两个模块谁先谁后、单开哪个,结果都合理。
        code = os.environ.get("GSI_CODENAME", "")
        for key in ("ro.build.flavor", "ro.build.description"):
            hit = False
            for i, l in enumerate(lines):
                if code and l.startswith(f"{key}={code}-user"):
                    lines[i] = l.replace(f"={code}-user", f"={dev}-user", 1)
                    hit = True
            if not hit:
                print(f"product_fields: {key} 不是以 {code}-user 开头,没改"
                      "(已经是别的值,比如 build-fingerprint 先跑过)", file=sys.stderr)
    elif part == "product":
        if not set_all("ro.quick_start.device_id", dev, required=False):
            print("product_fields: product 里没有 ro.quick_start.device_id,跳过", file=sys.stderr)

    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
