#!/usr/bin/env python3
"""用原厂固件的真实值生成 keymint 的默认 profile(pif_fingerprint.json)。

  make_profile.py <原厂 system/build.prop> <原厂 vendor build.prop> --brand B --device D --manufacturer M --model MD --product P > pif_fingerprint.json

字段和 herald-core 里私有种子(Pixel 7)是同一套 schema(version 2)。差别:值全是本机真实值,spoof_vending_build 为 false。
缺任何一个必要的 key 就失败,不会默默写出一个残缺的 profile。
"""
import argparse
import json
import sys


def props(path):
    d = {}
    for l in open(path, encoding="utf-8").read().splitlines():
        if "=" in l and not l.lstrip().startswith("#"):
            k, v = l.split("=", 1)
            d.setdefault(k, v)
    return d


ap = argparse.ArgumentParser()
ap.add_argument("system_prop"); ap.add_argument("vendor_prop")
for k in ("brand", "device", "manufacturer", "model", "product"):
    ap.add_argument("--" + k, required=True)
a = ap.parse_args()
s, v = props(a.system_prop), props(a.vendor_prop)


def need(d, k, where):
    if not d.get(k):
        sys.exit(f"make_profile: {where} 里没有 {k}")
    return d[k]


first_api = need(v, "ro.product.first_api_level", "原厂 vendor build.prop")
profile = {
    "version": 2,
    "model": a.model,
    "product": a.product,
    "manufacturer": a.manufacturer,
    # 原厂 system/build.prop 里常常没有裸的 ro.build.fingerprint,只有 ro.system.build.fingerprint(两者值相同)
    "fingerprint": s.get("ro.build.fingerprint") or need(s, "ro.system.build.fingerprint", "原厂 system build.prop"),
    "brand": a.brand,
    "device": a.device,
    "release": need(s, "ro.build.version.release", "原厂 system build.prop"),
    "id": need(s, "ro.build.id", "原厂 system build.prop"),
    "incremental": need(s, "ro.build.version.incremental", "原厂 system build.prop"),
    "build_type": need(s, "ro.build.type", "原厂 system build.prop"),
    "tags": need(s, "ro.build.tags", "原厂 system build.prop"),
    "security_patch": need(s, "ro.build.version.security_patch", "原厂 system build.prop"),
    "device_initial_sdk_int": int(first_api),
    "spoof_vending_build": False,
}
print(json.dumps(profile, ensure_ascii=False, separators=(",", ":")))
