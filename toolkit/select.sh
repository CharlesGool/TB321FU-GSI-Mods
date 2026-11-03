#!/usr/bin/env bash
# 看 / 挑这次要打的补丁。规则写法见 toolkit/lib/select.sh 开头。
#
# 用法: toolkit/select.sh <device.conf> [--profile P] [--with 规则] [--without 规则] [动作]
#   (不写动作)  打印按当前规则算出来的选择
#   --list       列出目录里全部补丁:[x] 这次打 / [ ] 不打,阶段、依赖、一句话说明
#   --info 补丁  打印一个补丁的 patch.conf 和谁依赖它
#   --menu       勾选菜单(whiptail),选完打印对应的预设内容
#   --save 名字  把当前选择(或 --menu 的结果)存成 devices/<设备>/profiles/<名字>.txt,
#                以后 PROFILE=<名字> 构建 system / 固件 / 9008 包都用同一份
# 环境变量 PROFILE / WITH / WITHOUT 和参数效果一样(参数追加在后面)。
set -euo pipefail
[[ $# -ge 1 ]] || { sed -n '2,12p' "$0"; exit 1; }
CONF=$(realpath "$1"); shift
TOOLKIT=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$TOOLKIT"); DEVICE_DIR=$(dirname "$CONF")
# shellcheck disable=SC1090
source "$CONF"
source "$TOOLKIT/lib/select.sh"
select_args "$@"
set -- "${SEL_REST[@]}"
ACTION=show SAVE= INFO=
while (( $# )); do
    case $1 in
        --list) ACTION=list; shift ;;
        --menu) ACTION=menu; shift ;;
        --info) ACTION=info; INFO=$2; shift 2 ;;
        --save) SAVE=$2; shift 2
                [[ $SAVE =~ ^[A-Za-z0-9._-]+$ ]] || { echo "--save 只要名字(字母数字 . _ -),存到 devices/<设备>/profiles/<名字>.txt" >&2; exit 1; } ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "不认识的参数 $1" >&2; exit 1 ;;
    esac
done
select_resolve || exit 1

meta() { _sel_meta "$1" "$2" | paste -sd' ' -; }
desc() { ( DESC=; source "$REPO/patches/$1/patch.conf"; echo "$DESC" ); }
title() { ( TITLE=; source "$REPO/patches/$1/patch.conf"; echo "$TITLE" ); }
stage_of() { case $(_sel_stage "$1") in firmware) echo boot;; both) echo system+boot;; *) echo system;; esac; }
chosen() { _sel_in "$1" "${SEL_MODS[@]}"; }

# 当前选择相对默认的差别 → 预设文件内容
profile_text() {
    echo "# $(select_desc)"
    echo "# 由 toolkit/select.sh 生成;一行一条:+补丁 / -补丁(也可以写文件夹或通配,见 toolkit/lib/select.sh)"
    local m
    for m in "${SEL_ALL[@]}"; do
        if chosen "$m"; then _sel_in "$m" "${MODS_OFF[@]}" && echo "+$m"
        else _sel_in "$m" "${MODS_OFF[@]}" || echo "-$m"; fi
    done
}

case $ACTION in
    show)
        select_summary ;;
    list)
        printf '%-3s %-11s %-32s %s\n' '' 阶段 补丁 中文名
        for m in "${SEL_ALL[@]}"; do
            mark='[ ]'; chosen "$m" && mark='[x]'
            req=$(meta "$m" REQUIRES)
            printf '%s %-11s %-32s %s%s\n' "$mark" "$(stage_of "$m")" "$m" "$(title "$m")" "${req:+  (要 $req)}"
        done
        echo; select_summary | head -2 ;;
    info)
        f=$REPO/patches/$INFO/patch.conf
        [[ -f $f ]] || { echo "没有 patches/$INFO/patch.conf" >&2; exit 1; }
        echo "== patches/$INFO/patch.conf"; cat "$f"
        echo; echo "== 谁依赖它"
        for m in "${SEL_ALL[@]}"; do
            _sel_deps "$m" | grep -qxF -- "$INFO" && echo "  $m"
        done; true
        echo; echo "== 这次: $(chosen "$INFO" && echo 打 || echo 不打)" ;;
    menu)
        command -v whiptail >/dev/null || { echo "没有 whiptail(apt install whiptail)" >&2; exit 1; }
        items=()
        for m in "${SEL_ALL[@]}"; do
            items+=("$m" "$(title "$m")" "$(chosen "$m" && echo ON || echo OFF)")
        done
        picked=$(whiptail --title "选补丁($(basename "$DEVICE_DIR"))" --separate-output \
            --checklist "空格勾选,回车确定。依赖会自动补上" 40 120 30 "${items[@]}" 3>&1 1>&2 2>&3) || { echo "取消了"; exit 1; }
        PROFILE= WITHOUT=; WITH=$(paste -sd, - <<< "$picked")
        tmp=$(mktemp); { echo -all; sed 's/^/+/' <<< "$picked"; } > "$tmp"
        PROFILE=$tmp WITH=; select_resolve || { rm -f "$tmp"; exit 1; }
        rm -f "$tmp"; PROFILE='(菜单)'
        select_summary ;;
esac

if [[ -n $SAVE || $ACTION == menu ]]; then
    if [[ -n $SAVE ]]; then
        mkdir -p "$DEVICE_DIR/profiles"
        out=$DEVICE_DIR/profiles/$SAVE.txt
        profile_text > "$out"
        echo; echo "存好了: $out"
        echo "用法: make build PROFILE=$SAVE   /   make 9008 PROFILE=$SAVE NOTE=…"
    else
        echo; echo "== 对应的预设内容(加 --save 名字 存起来):"; profile_text
    fi
fi
