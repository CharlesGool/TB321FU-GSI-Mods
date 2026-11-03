#!/usr/bin/env bash
# 给现成的 APK 打 smali 补丁:apktool 只解 dex(资源不解码)→ 跑补丁命令 → 回编 → 只把改过的 classesN.dex 换回原 APK
# (其余条目原样,压缩方式不变,原签名去掉)→ zipalign -p 4 → apksigner 重签 → 校验。
# 补丁命令也可以直接改解出目录里原样拷出来的文件(如 res/xx.json 这种 raw 资源),改过的同名条目一起换掉;
# 只能改原 APK 里已有的条目,resources.arsc、AndroidManifest.xml 不许改。
#
# 用法: apk-smali.sh <输入 apk> <输出 apk> <补丁命令> [参数…]
#   补丁命令最后会多收到一个参数:解出来的目录(里面是 smali/、smali_classes2/ …)。补丁命令非 0 退出则整体失败。
# 环境变量: APKTOOL_JAR(必需,apktool 2.12.x)
#           APK_KEY_DIR(签名 key 目录,默认仓库 private/overlay-key;里面要有 overlay.pk8 + overlay.x509.pem,没有就现生成一把自签的)
# 需要: java zipalign apksigner python3 openssl unzip
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2"); shift 2
[[ $# -ge 1 ]] || { echo "apk-smali: 缺补丁命令"; exit 2; }
: "${APKTOOL_JAR:?apk-smali: 要设 APKTOOL_JAR}"
REPO=$(cd "$(dirname "$0")/../.." && pwd)
KEYDIR=${APK_KEY_DIR:-$REPO/private/overlay-key}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

java -jar "$APKTOOL_JAR" d -r --no-assets -f -o "$T/dec" "$IN" > "$T/d.log" 2>&1 || { tail -20 "$T/d.log"; echo "apk-smali: apktool 解包失败"; exit 1; }
touch "$T/marker"; sleep 1
"$@" "$T/dec" || { echo "apk-smali: 补丁命令失败: $*"; exit 1; }

# 哪些 smali 目录被改过 → 对应哪个 dex
changed=()
for d in "$T"/dec/smali "$T"/dec/smali_classes*; do
    [[ -d $d ]] || continue
    if [[ -n $(find "$d" -type f -newer "$T/marker" -print -quit) ]]; then
        b=$(basename "$d"); [[ $b == smali ]] && changed+=(classes.dex) || changed+=("${b#smali_}.dex")
    fi
done
# 改过的原样文件(smali 目录、apktool.yml 之外)→ 同名条目
files=()
while IFS= read -r f; do
    rel=${f#"$T/dec/"}
    case $rel in smali/*|smali_classes*/*|apktool.yml) continue ;; resources.arsc|AndroidManifest.xml) echo "apk-smali: 不许改 $rel"; exit 1 ;; esac
    unzip -l "$IN" "$rel" >/dev/null 2>&1 || { echo "apk-smali: 原 APK 里没有条目 $rel,只能改已有的"; exit 1; }
    files+=("$rel")
done < <(find "$T/dec" -type f -newer "$T/marker")
[[ ${#changed[@]} -gt 0 || ${#files[@]} -gt 0 ]] || { echo "apk-smali: 补丁命令什么都没改"; exit 1; }

: > "$T/swap.list"
if [[ ${#changed[@]} -gt 0 ]]; then
    java -jar "$APKTOOL_JAR" b -f -o "$T/rebuilt.apk" "$T/dec" > "$T/b.log" 2>&1 || { tail -20 "$T/b.log"; echo "apk-smali: apktool 回编失败"; exit 1; }
    mkdir "$T/dex"
    for x in "${changed[@]}"; do
        unzip -p "$T/rebuilt.apk" "$x" > "$T/dex/$x"; [[ -s $T/dex/$x ]] || { echo "apk-smali: 回编结果里没有 $x"; exit 1; }
        printf '%s\t%s\n' "$x" "$T/dex/$x" >> "$T/swap.list"
    done
fi
for rel in "${files[@]}"; do printf '%s\t%s\n' "$rel" "$T/dec/$rel" >> "$T/swap.list"; done
python3 -I - "$IN" "$T/swap.list" "$T/swapped.apk" <<'PY'
import sys, zipfile
src, lst, out = sys.argv[1:4]
new = dict(l.rstrip('\n').split('\t', 1) for l in open(lst, encoding='utf-8') if l.strip())
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(out, 'w') as zo:
    for it in zi.infolist():
        n = it.filename
        if n.startswith('META-INF/') and (n.endswith(('.SF', '.RSA', '.DSA', '.EC')) or n == 'META-INF/MANIFEST.MF'):
            continue
        data = open(new[n], 'rb').read() if n in new else zi.read(n)
        ni = zipfile.ZipInfo(n, it.date_time); ni.compress_type = it.compress_type; ni.external_attr = it.external_attr
        zo.writestr(ni, data)
PY
zipalign -f -p 4 "$T/swapped.apk" "$T/aligned.apk"
if [[ ! -f $KEYDIR/overlay.pk8 || ! -f $KEYDIR/overlay.x509.pem ]]; then
    mkdir -p "$KEYDIR"
    openssl req -x509 -newkey rsa:2048 -nodes -days 10000 -subj "/CN=herald-overlay" \
        -keyout "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.x509.pem" 2>/dev/null
    openssl pkcs8 -topk8 -nocrypt -inform PEM -outform DER -in "$KEYDIR/overlay.key.pem" -out "$KEYDIR/overlay.pk8"
    rm -f "$KEYDIR/overlay.key.pem"
fi
mkdir -p "$(dirname "$OUT")"
apksigner sign --key "$KEYDIR/overlay.pk8" --cert "$KEYDIR/overlay.x509.pem" --out "$OUT" "$T/aligned.apk"
rm -f "$OUT.idsig"
apksigner verify "$OUT" >/dev/null || { echo "apk-smali: 签名校验失败"; exit 1; }
zipalign -c -p 4 "$OUT" || { echo "apk-smali: 签名后没对齐"; exit 1; }
echo "apk-smali: 换了 ${changed[*]} ${files[*]} → $OUT"
