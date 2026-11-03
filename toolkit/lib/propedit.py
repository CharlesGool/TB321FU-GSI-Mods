#!/usr/bin/env python3
"""build.prop 编辑。由 common.sh 的 prop() 调用,也可以单独用。

  propedit.py set <key> <value> [--add] <file>   所有 key=... 改成 key=value;不存在时 --add 追加,否则报错
  propedit.py del <key> <file>                   删除所有 key=... 行
  propedit.py overlay <overlay.prop> [--add-missing|--strict] <file>
        把 overlay 里的每个 key=value 应用到 file:已存在的就地改;
        不存在的:--add-missing 追加,--strict 报错退出,都不给就跳过
"""
import sys


def load(path):
    return open(path, encoding="utf-8").read().splitlines()


def save(path, lines):
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def keyof(line):
    s = line.strip()
    if not s or s.startswith("#") or "=" not in s:
        return None
    return line.split("=", 1)[0]


def set_value(lines, key, value, add):
    n = 0
    for i, line in enumerate(lines):
        if keyof(line) == key:
            lines[i] = f"{key}={value}"
            n += 1
    if not n:
        if not add:
            sys.exit(f"propedit: 找不到 {key}(要追加请加 --add)")
        lines.append(f"{key}={value}")
    return n


def main():
    op, args = sys.argv[1], sys.argv[2:]
    path = args[-1]
    lines = load(path)
    if op == "set":
        set_value(lines, args[0], args[1], "--add" in args[2:-1])
    elif op == "del":
        lines = [l for l in lines if keyof(l) != args[0]]
    elif op == "overlay":
        add_missing = "--add-missing" in args[1:-1]
        strict = "--strict" in args[1:-1]
        changed, added, skipped = 0, [], []
        for ol in load(args[0]):
            k = keyof(ol)
            if k is None:
                continue
            v = ol.split("=", 1)[1]
            if any(keyof(l) == k for l in lines):
                set_value(lines, k, v, False)
                changed += 1
            elif add_missing:
                lines.append(f"{k}={v}")
                added.append(k)
            elif strict:
                sys.exit(f"propedit: 找不到 {k}(--strict)")
            else:
                skipped.append(k)
        print(f"overlay: 改 {changed} 追加 {len(added)} 跳过 {len(skipped)}", file=sys.stderr)
    else:
        sys.exit(f"propedit: 不认识的操作 {op}")
    save(path, lines)


if __name__ == "__main__":
    main()
