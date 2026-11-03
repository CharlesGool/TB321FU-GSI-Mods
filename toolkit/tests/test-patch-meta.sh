#!/usr/bin/env bash
# 补丁身份文件(patch.conf)的检查:每个补丁都有、和 apply.sh 里的写法对得上、各设备目录的顺序满足它。
# 用法: toolkit/tests/test-patch-meta.sh      (不构建,几秒钟)
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fail=0; n=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
same() { [[ "$(printf '%s\n' $1 | sed '/^$/d' | sort -u)" == "$(printf '%s\n' $2 | sed '/^$/d' | sort -u)" ]]; }

mapfile -t PATCHES < <(cd "$REPO/patches" && find . -name apply.sh -printf '%h\n' | sed 's|^\./||' | sort)
for p in "${PATCHES[@]}"; do
    n=$((n + 1)); d=$REPO/patches/$p; f=$d/patch.conf
    [[ -f $f ]] || { bad "$p: 没有 patch.conf"; continue; }
    [[ -f $d/README.md ]] || bad "$p: 没有 README.md"
    [[ -x $d/apply.sh ]] || bad "$p: apply.sh 不可执行"
    eval "$(NAME= VERSION= TITLE= DESC= STAGE= REQUIRES=() AFTER=() BEFORE=() CONTRIBUTES=() ASSEMBLES=() WANTS=() RUNTIME= RISKS=
            source "$f"
            printf 'M_TITLE=%q M_NAME=%q M_VER=%q M_DESC=%q M_STAGE=%q M_REQ=%q M_AFTER=%q M_BEFORE=%q M_CON=%q M_ASM=%q M_WANTS=%q\n' \
              "$TITLE" "$NAME" "$VERSION" "$DESC" "$STAGE" "${REQUIRES[*]}" "${AFTER[*]}" "${BEFORE[*]}" "${CONTRIBUTES[*]}" "${ASSEMBLES[*]}" "${WANTS[*]}")"
    [[ $M_NAME == "$p" ]] || bad "$p: NAME=$M_NAME 和文件夹不一致"
    [[ -n $M_DESC ]] || bad "$p: DESC 是空的"
    [[ -n $M_TITLE ]] || bad "$p: TITLE(中文名)是空的"
    # VERSION:补丁自己的版本号。格式 V<数字>.<数字>,可带后缀(如 V1.0-test)。每次改补丁都要升(下面 git 检查)
    [[ $M_VER =~ ^V[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)*$ ]] || bad "$p: VERSION=$M_VER 格式不对(要 V<数字>.<数字>,可带后缀,如 V1.0 / V1.0-test)"
    # git:补丁目录相对 HEAD 有改动(含未跟踪新文件),就必须升版本号——否则和 HEAD 里的 VERSION 一样就报错。
    # HEAD 里还没有这个补丁(新补丁),或 HEAD 的 patch.conf 还没有 VERSION(改革前的基线),都不算"没升"。
    if git -C "$REPO" rev-parse --verify -q HEAD >/dev/null 2>&1; then
        changed=0
        git -C "$REPO" diff --quiet HEAD -- "patches/$p" 2>/dev/null || changed=1
        [[ -n $(git -C "$REPO" ls-files --others --exclude-standard -- "patches/$p" 2>/dev/null) ]] && changed=1
        if (( changed )); then
            old_ver=$(git -C "$REPO" show "HEAD:patches/$p/patch.conf" 2>/dev/null | sed -n 's/^VERSION=//p' | head -1)
            if [[ -n $old_ver && $old_ver == "$M_VER" ]]; then
                bad "$p: 补丁相对 HEAD 有改动,但 VERSION 没升(仍是 $M_VER)——改补丁必须更新版本号(patch.conf 的 VERSION)"
            fi
        fi
    fi
    [[ $M_STAGE == system || $M_STAGE == firmware || $M_STAGE == both ]] || bad "$p: STAGE=$M_STAGE(只能 system / firmware / both,说明改的是哪边)"
    src=$d/apply.sh
    req=$(grep -ho '^[[:space:]]*require_mod[[:space:]]\+[^[:space:]#]\+' "$src" | awk '{print $2}')
    same "$req" "$M_REQ" || bad "$p: apply.sh 里 require_mod 的是 [$(echo $req)],patch.conf 的 REQUIRES 是 [$M_REQ]"
    all_src=("$src"); [[ -d $d/parts ]] && all_src+=("$d"/parts/*/part.sh)
    con=$(grep -ho 'contrib_add\(_text\)\?[[:space:]]\+[a-zA-Z0-9_-]\+' "${all_src[@]}" | awk '{print $2}')
    same "$con" "$M_CON" || bad "$p: apply.sh 往 [$(echo $con)] 登记,patch.conf 的 CONTRIBUTES 是 [$M_CON]"
    if grep -q contrib_consume "${all_src[@]}"; then [[ -n $M_ASM ]] || bad "$p: apply.sh 调了 contrib_consume,patch.conf 的 ASSEMBLES 是空的"
    else [[ -z $M_ASM ]] || bad "$p: ASSEMBLES=[$M_ASM],但 apply.sh 没调 contrib_consume"; fi
    grep -q '^PARTS=' "$f" && bad "$p: patch.conf 不再写 PARTS,部分的顺序看 parts/ 下的编号"
    if [[ -d $d/parts ]]; then
        want=1
        for x in $(cd "$d/parts" && ls); do
            [[ -d $d/parts/$x ]] || { bad "$p: parts/$x 不是文件夹"; continue; }
            [[ $x =~ ^([0-9]{3})\.[a-z0-9][a-z0-9-]*$ ]] || { bad "$p: parts/$x 要叫 NNN.<部分名>(如 001.node-access)"; continue; }
            (( 10#${BASH_REMATCH[1]} == want )) || bad "$p: parts/$x 的编号应该是 $(printf %03d $want)(从 001 连续)"
            want=$((want + 1))
            [[ -f $d/parts/$x/part.sh ]] || bad "$p: parts/$x 没有 part.sh"
            [[ -f $d/parts/$x/README.md ]] || bad "$p: parts/$x 没有 README.md"
            [[ ! -f $d/parts/$x/apply.sh && ! -f $d/parts/$x/patch.conf ]] || bad "$p: parts/$x 里不该有 apply.sh / patch.conf(部分不是补丁)"
            ! grep -q '^[[:space:]]*require_mod' "$d/parts/$x/part.sh" || bad "$p: parts/$x/part.sh 里有 require_mod(部分之间靠编号,外部依赖写在补丁的 apply.sh)"
        done
        grep -q '^run_parts' "$src" || bad "$p: 有 parts/ 但 apply.sh 没调 run_parts"
    fi
    if grep -q '^[^#]*mark_modified' "${all_src[@]}" && [[ $p != required/general/boot-kernel/stale-boot-image ]]; then
        [[ " $M_WANTS " == *" required/general/boot-kernel/stale-boot-image "* ]] || bad "$p: 改了 jar(mark_modified)但 patch.conf 没有 WANTS=(stale-boot-image)"
    fi
    for x in $M_REQ $M_AFTER $M_BEFORE $M_WANTS; do [[ -f $REPO/patches/$x/apply.sh ]] || bad "$p: 引用了不存在的补丁 $x"; done
done

# 各设备目录:列的补丁都存在、顺序满足 patch.conf
for conf in "$REPO"/devices/*/device*.conf; do
    out=$(REPO=$REPO DEVICE_DIR=$(dirname "$conf") bash -c '
        source "$1"; source "$REPO/toolkit/lib/select.sh"
        select_check_order 2>&1 || true
        select_resolve >/dev/null 2>&1 || echo "默认选择算不出来"' _ "$conf")
    if [[ -n $out ]]; then while IFS= read -r l; do bad "${conf#$REPO/}: $l"; done <<< "$out"; fi
done

# optional/* 的 DEFAULT 字段(make-9008.sh 向导问"要吗?"的默认答案,只是说明性的,不驱动向导逻辑——向导
# 真正用的是各设备自己 device.conf 的 MODS_OFF,devices 之间本来就有意不一样,如 bp1a/tangobeta)要和主设备
# tb321fu-a15/device.conf 的 MODS_OFF 对得上,免得主设备这边两份说明各说各的。
MAIN_CONF=$REPO/devices/tb321fu-a15/device.conf
if [[ -f $MAIN_CONF ]]; then
    out=$(REPO=$REPO DEVICE_DIR=$(dirname "$MAIN_CONF") bash -c '
        source "$1"; source "$REPO/toolkit/lib/select.sh"
        for m in $(_sel_catalog); do
            case $m in
                optional/*) ;;
                *) continue ;;
            esac
            d=$(_sel_default "$m")
            if _sel_in "$m" "${MODS_OFF[@]}"; then
                [[ $d == off ]] || echo "$m: 在 MODS_OFF 里,但 patch.conf 的 DEFAULT 不是 off(是 $d)"
            else
                [[ $d == on ]] || echo "$m: DEFAULT=off,但没在 MODS_OFF 里(两边不一致)"
            fi
        done' _ "$MAIN_CONF")
    if [[ -n $out ]]; then while IFS= read -r l; do bad "${MAIN_CONF#$REPO/}: $l"; done <<< "$out"; fi
fi

"$REPO/toolkit/gen-index.sh" --check || bad "补丁总表 patches/README.md 过期"

echo "检查了 ${n} 个补丁,失败 $fail 项"
(( fail == 0 ))
