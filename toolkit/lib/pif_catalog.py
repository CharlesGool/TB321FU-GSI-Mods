#!/usr/bin/env python3
"""拉取 Pixel 机型列表和机型配置(KOWX712/PlayIntegrityFix 的 bot 分支,每天从 Google 官方页面刷新)。

  pif_catalog.py list                 打印机型列表,每行 "序号<TAB>product<TAB>型号"
  pif_catalog.py get <product> <out>  下载这个机型的配置(.prop),校验后写到 <out>
  pif_catalog.py check <file.prop>    只校验一个本地 .prop

和 herald-core 引擎里"伪装 PIF 指纹"用的是同一份数据、同样的校验:先试 GitHub Raw,再试 jsDelivr;
列表上限 64 KiB、配置上限 4 KiB;配置必须有 FINGERPRINT MANUFACTURER MODEL SECURITY_PATCH,
DEVICE_INITIAL_SDK_INT 可选(正整数);未知键、重复键都拒绝。
"""
import json
import re
import sys
import urllib.request

BASES = ["https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/bot",
         "https://fastly.jsdelivr.net/gh/KOWX712/PlayIntegrityFix@bot",
         "https://cdn.jsdelivr.net/gh/KOWX712/PlayIntegrityFix@bot"]
MAX_CATALOG, MAX_PROP = 64 * 1024, 4 * 1024
REQUIRED = ("FINGERPRINT", "MANUFACTURER", "MODEL", "SECURITY_PATCH")
ALLOWED = REQUIRED + ("DEVICE_INITIAL_SDK_INT",)
PRODUCT_RE = re.compile(r"^[a-z0-9_]{1,64}$")
FP_RE = re.compile(r"^[^/\s]+/[^/\s]+/[^/:\s]+:[^/\s]+/[^/\s]+/[^/:\s]+:[^/\s]+/[^/\s]+$")


def fetch(rel, limit):
    err = []
    for base in BASES:
        try:
            with urllib.request.urlopen(urllib.request.Request(f"{base}/{rel}", headers={"User-Agent": "tb321fu-mods"}), timeout=15) as r:
                data = r.read(limit + 1)
            if len(data) > limit:
                err.append(f"{base}: 超过 {limit} 字节")
                continue
            return data.decode("utf-8")
        except Exception as e:  # 网络层各种错都换下一个源
            err.append(f"{base}: {e}")
    sys.exit("下载失败:\n  " + "\n  ".join(err))


def parse_catalog(text):
    try:
        items = json.loads(text)
    except ValueError as e:
        sys.exit(f"机型列表不是合法 JSON: {e}")
    if not isinstance(items, list) or not items:
        sys.exit("机型列表为空或格式不对")
    out = []
    for it in items:
        if not (isinstance(it, dict) and isinstance(it.get("product"), str) and isinstance(it.get("model"), str)):
            sys.exit(f"机型列表里有不合格的条目: {it!r}")
        if not PRODUCT_RE.match(it["product"]):
            sys.exit(f"机型列表里的 product 不合法: {it['product']!r}")
        out.append((it["product"], it["model"]))
    return out


def parse_prop(text):
    d = {}
    for n, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            sys.exit(f"配置第 {n} 行不是 KEY=VALUE: {line!r}")
        k, v = line.split("=", 1)
        if k not in ALLOWED:
            sys.exit(f"配置里有不认识的键 {k}")
        if k in d:
            sys.exit(f"配置里的键 {k} 重复")
        d[k] = v
    for k in REQUIRED:
        if not d.get(k):
            sys.exit(f"配置缺 {k}")
    if not FP_RE.match(d["FINGERPRINT"]):
        sys.exit(f"FINGERPRINT 格式不对: {d['FINGERPRINT']!r}")
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", d["SECURITY_PATCH"]):
        sys.exit(f"SECURITY_PATCH 要写成 YYYY-MM-DD: {d['SECURITY_PATCH']!r}")
    if "DEVICE_INITIAL_SDK_INT" in d and not re.match(r"^[1-9][0-9]{0,9}$", d["DEVICE_INITIAL_SDK_INT"]):
        sys.exit("DEVICE_INITIAL_SDK_INT 要是正整数")
    return d


def main():
    a = sys.argv[1:]
    if a[:1] == ["list"] and len(a) == 1:
        for i, (p, m) in enumerate(parse_catalog(fetch("device_list.json", MAX_CATALOG)), 1):
            print(f"{i}\t{p}\t{m}")
    elif a[:1] == ["get"] and len(a) == 3:
        if not PRODUCT_RE.match(a[1]):
            sys.exit("product 不合法")
        text = fetch(f"device_prop/{a[1]}.prop", MAX_PROP)
        parse_prop(text)
        open(a[2], "w", encoding="utf-8").write(text if text.endswith("\n") else text + "\n")
    elif a[:1] == ["check"] and len(a) == 2:
        parse_prop(open(a[1], encoding="utf-8").read())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
