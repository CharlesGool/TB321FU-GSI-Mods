#!/usr/bin/env bash
# 批量清理 releases/ 下的旧构建,正式版永不删除。
#
# 正式版的判定(满足任一即"受保护",本脚本绝不删):
#   1. 目录名里带 user-v(正式版命名约定,如 pixelos_..._user-v1.0_optional、V97-PIF 不算)
#   2. 目录里有 KEEP 标记文件(手动 touch <目录>/KEEP 即可把任意版本标成正式版)
#
# 用法:
#   clean-releases.sh --list                 列出所有版本,标出哪些受保护 / 可删
#   clean-releases.sh --tests                 预演:列出所有 test-v* 构建(受保护的除外)
#   clean-releases.sh --tests --apply         真的删掉上面那些 test-v* 构建
#   clean-releases.sh <名字> [名字…]          预演:删这些指定目录(受保护的会被拒)
#   clean-releases.sh <名字> [名字…] --apply  真的删(受保护的仍被硬性跳过)
#
# 不加 --apply 一律只预演(打印会删什么),不动任何文件。
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REL=$(cd "$HERE/../.." && pwd)/releases
[[ -d $REL ]] || { echo "找不到 releases 目录: $REL" >&2; exit 1; }

APPLY=0; MODE=; NAMES=()
for a in "$@"; do
    case $a in
        --apply) APPLY=1 ;;
        --list)  MODE=list ;;
        --tests) MODE=tests ;;
        --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
        -*) echo "不认识的参数: $a" >&2; exit 1 ;;
        *) NAMES+=("$a") ;;
    esac
done

protected() {  # $1=目录名;受保护返回 0
    local d=$1
    [[ $d == *user-v* ]] && return 0
    [[ -f $REL/$d/KEEP ]] && return 0
    return 1
}

mapfile -t ALL < <(cd "$REL" && for d in */; do echo "${d%/}"; done)

if [[ $MODE == list || ( -z $MODE && ${#NAMES[@]} -eq 0 ) ]]; then
    printf '%-70s %s\n' "版本目录" "状态"
    for d in "${ALL[@]}"; do
        if protected "$d"; then printf '%-70s %s\n' "$d" "★ 正式版(受保护,不删)"
        else printf '%-70s %s\n' "$d" "可删"; fi
    done
    exit 0
fi

TARGETS=()
if [[ $MODE == tests ]]; then
    for d in "${ALL[@]}"; do [[ $d == *test-v* ]] && TARGETS+=("$d"); done
else
    TARGETS=("${NAMES[@]}")
fi

to_del=(); skipped=()
for d in "${TARGETS[@]}"; do
    d=${d%/}
    if [[ ! -d $REL/$d ]]; then echo "跳过(不存在): $d" >&2; continue; fi
    if protected "$d"; then skipped+=("$d"); else to_del+=("$d"); fi
done

(( ${#skipped[@]} )) && { echo "受保护、不删的正式版:"; printf '  ★ %s\n' "${skipped[@]}"; }
if (( ${#to_del[@]} == 0 )); then echo "没有可删的目标。"; exit 0; fi

echo "${APPLY:+将删除}${APPLY:-预演(加 --apply 才真的删)—— 会删除}以下 ${#to_del[@]} 个版本:"
du -sh "${to_del[@]/#/$REL/}" 2>/dev/null | sed 's#'"$REL"'/#  #'
if (( APPLY )); then
    for d in "${to_del[@]}"; do sudo rm -rf "$REL/$d" && echo "已删: $d"; done
else
    echo "(预演结束,未删除任何文件)"
fi
