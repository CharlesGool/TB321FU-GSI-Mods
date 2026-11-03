#!/usr/bin/env bash
# 从各补丁的 patch.conf 生成补丁总表 patches/README.md。改了 patch.conf(或加/删补丁)后跑一下;
# toolkit/tests/test-patch-meta.sh 会检查总表是不是最新的。
# 用法: toolkit/gen-index.sh [--check]   --check 只比较不写,过期返回 1
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=$REPO/patches/README.md
CONF=${CONF:-$REPO/devices/tb321fu-a15/device.conf}   # 排序和"默认"一栏按这份设备配置的默认选择

# 输出 "打|不打|自动<TAB>补丁":默认会打的在前,再是默认不打的;两组内部按执行顺序
order() {
    REPO=$REPO DEVICE_DIR=$(dirname "$CONF") bash -c '
        source "$1"; source "$REPO/toolkit/lib/select.sh"; select_resolve >/dev/null || exit 1
        for m in "${SEL_ALL[@]}"; do
            if _sel_in "$m" "${SEL_MODS[@]}"; then
                _sel_in "$m" "${MODS_OFF[@]}" && printf "自动\t%s\n" "$m" || printf "打\t%s\n" "$m"
            fi
        done
        for m in "${SEL_ALL[@]}"; do _sel_in "$m" "${SEL_MODS[@]}" || printf "不打\t%s\n" "$m"; done' _ "$CONF"
    # 不在这份配置目录里的补丁放最后
    comm -23 <(cd "$REPO/patches" && find . -name patch.conf -printf '%h\n' | sed 's|^\./||' | sort) \
             <(REPO=$REPO bash -c 'source "$1"; printf "%s\n" "${MODS[@]}"' _ "$CONF" | sort -u) | sed 's/^/不在目录\t/'
}

gen() {
    cat <<'EOF'
# 补丁总表

> 由 `toolkit/gen-index.sh` 从各补丁的 `patch.conf` 生成,不要手改。每个补丁的原理看它自己的 README。

补丁按用途放在四个文件夹里,**补丁名就是 `patches/` 下的路径**(选补丁时可以写末尾几段的短名,如 `battery`、`slim`):

- `required/general/` **必须打 · 通用修复**:这个项目是为 TB321FU 做的,所以不管用哪个 GSI 都要打的修复都在这里(按类分文件夹:`hardware-fix/` 硬件功能修复、`bug-fix/` 漏洞修复、`slim/` 精简、`boot-kernel/` boot 和内核、`herald-core`)。
- `required/<底包前缀>/` **必须打 · 特定底包限定**:只有某类 GSI 才需要的修复。文件夹名是底包 ID 的前缀,构建时只有底包 ID 命中才跑(`required/tangorpro/` = 所有 Pixel Tablet 的 GSI:屏幕方向、热点入口;里面再套 `tangorpro_ap3a.241005.015/` = 只有这一版)。底包 ID 取自底包指纹,日志第一行会打印。
- `optional/` **可选**:给用户用的功能,按需选;高级或非原生的默认不打。
- `debug/` **调试**:开发排错、调研、诊断用的补丁(抓日志、探针、root 只读命令…),正常使用不需要,默认都不打;要用时 `WITH=debug` 一次选上。

每个表内按执行顺序(device.conf 的 `MODS`)排,"默认"一栏按 `devices/tb321fu-a15/device.conf`:"打"= 默认打,"不打"= 默认不打,"自动"= 本身不在默认里、但被别的补丁自动带上。大类文件夹(`slim/`、`brightness/`…)本身不是补丁,只用来一次选一批。合并补丁(`battery`、`tango`…)内部的部分(`parts/001.xxx`…,按编号顺序跑)在"包含"一栏,不能单独选。
"要先有"是 `REQUIRES`(选了会自动带上);"登记到"是 `CONTRIBUTES`(会自动带上负责它的 assemble 补丁)。

EOF
    local -a rows=()
    mapfile -t rows < <(order)
    local sec title def p i r
    local -a secs=(required/general)
    local d
    for d in "$REPO"/patches/required/*/; do [[ $(basename "$d") == general ]] || secs+=("required/$(basename "$d")"); done
    secs+=(optional debug)
    for sec in "${secs[@]}"; do
        case $sec in
            required/general) title='必须打 · 通用修复' ;;
            required/*) title="必须打 · 特定底包限定(${sec#required/})" ;;
            optional) title='可选' ;;
            debug) title='调试' ;;
        esac
        printf '## %s\n\n| 编号 | 中文名 | 补丁 | 改哪里 | 默认 | 做什么 | 包含 | 要先有 | 登记到 / 负责 | 运行时开关 | 可能的问题 |\n|---|---|---|---|---|---|---|---|---|---|---|\n' "$title"
        i=0
        for r in "${rows[@]}"; do
            IFS=$'\t' read -r def p <<< "$r"
            [[ $p == "$sec"/* ]] || continue
            i=$((i + 1))
            ( NAME= TITLE= DESC= STAGE= REQUIRES=() CONTRIBUTES=() ASSEMBLES=() RUNTIME= RISKS=
              PARTS=(); [[ -d $REPO/patches/$p/parts ]] && mapfile -t PARTS < <(cd "$REPO/patches/$p/parts" && ls -d [0-9][0-9][0-9].*)
              source "$REPO/patches/$p/patch.conf"
              rel=''; (( ${#CONTRIBUTES[@]} )) && rel="→ ${CONTRIBUTES[*]}"; (( ${#ASSEMBLES[@]} )) && rel="负责 ${ASSEMBLES[*]}"
              st=system; [[ $STAGE == firmware ]] && st=boot; [[ $STAGE == both ]] && st=system+boot
              inc=''; (( ${#PARTS[@]} )) && inc="${#PARTS[@]} 个部分:$(IFS=、; echo "${PARTS[*]}")"
              printf '| %d | %s | [%s](%s/) | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$i" "$TITLE" "${p#"$sec"/}" "$p" "$st" "$def" "${DESC//|/\\|}" "$inc" "${REQUIRES[*]}" "$rel" "${RUNTIME//|/\\|}" "${RISKS//|/\\|}" )
        done
        echo
    done
}

if [[ ${1:-} == --check ]]; then
    diff -q <(gen) "$OUT" >/dev/null || { echo "patches/README.md 过期了,跑 toolkit/gen-index.sh"; exit 1; }
else
    gen > "$OUT"; echo "写好 $OUT"
fi
