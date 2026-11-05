#!/usr/bin/env python3
"""保留 GSI 自带安卓版本的身份 overlay:只把 GSI 指纹的机型身份段换成本机型。

用法: gsi_overlay.py <GSI system/build.prop> > overlay.prop
环境变量: ID_BRAND ID_NAME ID_DEVICE

与 stock_overlay.py 的区别:不从原厂固件取指纹/版本,而是取 **GSI 自带** 的指纹,只重写其中的
brand/product/device 段(`A/B/C:...` 冒号前那段)成 `ID_BRAND/ID_NAME/ID_DEVICE`;版本段
(`:<release>/<id>/<incremental>:`)和 ro.build.version.* / security_patch / description / flavor
一律不动(由 GSI 决定),所以系统不会把安卓版本谎报成原厂 ZUI 的版本。

只产出 7 个 fingerprint 变体(与 stock_overlay 同形),其余版本字段留给 GSI。CP3A 这类
"底包比原厂新" 的场景用(ID_KEEP_GSI_OS_VERSION=1)。
"""
import os
import sys


def props(lines):
    d = {}
    for l in lines:
        if "=" in l and not l.lstrip().startswith("#"):
            k, v = l.split("=", 1)
            d.setdefault(k, v)
    return d


def main():
    gsi_sys = sys.argv[1]
    s = props(open(gsi_sys, encoding="utf-8").read().splitlines())
    # GSI 可能只有带分区前缀的指纹(常见 ro.system.build.fingerprint),裸 ro.build.fingerprint 不一定有
    fp = (s.get("ro.build.fingerprint") or s.get("ro.system.build.fingerprint")
          or s.get("ro.product.build.fingerprint"))
    if not fp:
        sys.exit("GSI system/build.prop 里没有 fingerprint(ro.build/ro.system.build/ro.product.build)")
    if ":" not in fp:
        sys.exit(f"GSI 指纹格式异常(缺 ':'): {fp}")

    brand = os.environ["ID_BRAND"]
    name = os.environ["ID_NAME"]
    device = os.environ["ID_DEVICE"]
    # 指纹格式: BRAND/PRODUCT/DEVICE:RELEASE/ID/INCREMENTAL:TYPE/TAGS
    # 只换冒号前的机型身份段,保留后面的版本段和 type/tags(GSI 的)。
    head, rest = fp.split(":", 1)
    new_fp = f"{brand}/{name}/{device}:{rest}"

    out = ["# 由 identity/parts/002.build-fingerprint/gsi_overlay.py 生成(保留 GSI 安卓版本,只换机型身份段),不要手改"]
    for part in ("", "system.", "product.", "vendor.", "odm.", "bootimage.", "system_ext."):
        out.append(f"ro.{part}build.fingerprint={new_fp}")

    # flavor / description:把开头的 "<GSI 机型代号>-user" 换成 "<ID_DEVICE>-user",后面的版本段(17 CP3A...)原样保留。
    # 三份 build.prop 的机型代号可能不一样(system 常被 MysticGSI 泛化成 generic_system_google,
    # product/system_ext 仍是 tangorpro),统一用 GSI system/build.prop 的值归一化后 overlay 进全部三份。
    def retag(v):
        i = v.find("-user")
        return device + v[i:] if i != -1 else None  # "<ID_DEVICE>-user[ <版本段>]"
    for key in ("ro.build.flavor", "ro.build.description"):
        v = s.get(key)
        if v:
            nv = retag(v)
            if nv:
                out.append(f"{key}={nv}")
    print("\n".join(out))


if __name__ == "__main__":
    main()
