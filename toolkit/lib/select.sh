# 选补丁:算出这次构建实际要打哪些补丁。build.sh、test-modules.sh、select.sh 共用。
#
# device.conf 的 MODS 是"目录":本设备全部可选的补丁和它们的执行顺序(改 system 的、改 boot 的都在里面)。MODS_OFF 里的默认不打。
# 选择规则从这几处来,按顺序叠加:
#   1. 默认:MODS 去掉 MODS_OFF
#   2. PROFILE=名字或路径   预设文件,一行一条规则(见下),找的顺序:路径本身 → devices/<设备>/profiles/<名字>.txt → profiles/<名字>.txt
#   2b. CAMERA=zui|pixel|none  相机三选一(联想相机 / Pixel 相机 / 都不装),device.conf 里有默认值
#   3. WITH=规则,规则…      加上
#   4. WITHOUT=规则,规则…   去掉
# 规则写法:
#   optional/battery、battery   一个补丁(全名或末尾几段的短名,如 battery、brightness/hbm-unlimited)
#   optional、slim、required/general   一个文件夹下的全部补丁(短名同理)
#   hotspot-*、tango/*     通配
#   必须打的在 required/(general 通用修复、<底包前缀> 特定底包限定,如 tangorpro),可选的在 optional/,调试用的在 debug/
#   all                    全部(包括默认不打的)
# 预设文件里每行写 "+规则" 或 "-规则"(不带符号算 +),# 开头是注释。"-all" 清空,从头挑。
#
# 依赖自动处理(读各补丁的 patch.conf):
#   - REQUIRES 里的:选了它就自动带上
#   - CONTRIBUTES 里的产物:自动带上 ASSEMBLES 这个产物的补丁
#   - ASSEMBLES 非空的(assemble 补丁):没人登记时原样输出,所以总是带上,除非明确点名去掉
#   - WANTS 里的(软依赖):选了就顺带打上,被明确去掉的不带,也不连累想要它的补丁(例:改 jar 的补丁 WANTS stale-boot-image)
#   被明确去掉的(WITHOUT 或预设里的 -规则,"-all" 不算)不会被自动带回来,依赖它的补丁跟着去掉。全部打印出来。
#
# 用法:source 本文件(之前要有 REPO 并已 source device.conf),然后
#   select_args "$@"   (可选)把 --profile/--with/--without 参数并进 PROFILE/WITH/WITHOUT;剩下的参数放进 SEL_REST
#   select_resolve     核对目录顺序,算出 SEL_MODS(按目录顺序);失败返回非 0
#   select_summary     打印选择结果(和默认比多了/少了什么)
#   select_record F    把规则和结果写进文件 F(构建输出目录里的 SELECTION.txt)
#   select_flavor      按 SEL_MODS 给出产物名后缀:选了 optional/ 下的补丁 → _optional,选了 debug/ 下的 → _debug,都选 → _optional_debug,只有 required → 空

SEL_REST=()
select_args() {
    SEL_REST=()
    while (( $# )); do
        case $1 in
            --profile) PROFILE=$2; shift 2 ;;
            --with)    WITH=${WITH:+$WITH,}$2; shift 2 ;;
            --without) WITHOUT=${WITHOUT:+$WITHOUT,}$2; shift 2 ;;
            *) SEL_REST+=("$1"); shift ;;
        esac
    done
}

# ---- 补丁目录 ----
_sel_catalog() { printf '%s\n' "${MODS[@]}" | awk '!seen[$0]++'; }
# _sel_stage <补丁> → patch.conf 的 STAGE(改哪边:system / firmware / both)
_sel_stage() { ( STAGE=system; source "$REPO/patches/$1/patch.conf"; echo "$STAGE" ); }
_sel_in() { local x n=$1; shift; for x in "$@"; do [[ $x == "$n" ]] && return 0; done; return 1; }

# _sel_match <规则> → 打印目录里匹配的补丁
_sel_match() {
    local r=${1%/} m
    while IFS= read -r m; do
        [[ -n $m ]] || continue
        # shellcheck disable=SC2053
        if [[ $r == all || $m == "$r" || $m == "$r"/* || $m == $r || $m == */"$r" || $m == */"$r"/* || $m == */$r ]]; then echo "$m"; fi
    done < <(_sel_catalog)
}

# _sel_meta <补丁> <字段>   读 patches/<补丁>/patch.conf 里的一个数组字段(REQUIRES AFTER BEFORE CONTRIBUTES ASSEMBLES WANTS),一行一个
_sel_meta() {
    local f=$REPO/patches/$1/patch.conf
    [[ -f $f ]] || { echo "缺 patches/$1/patch.conf" >&2; return 1; }
    ( REQUIRES=() AFTER=() BEFORE=() CONTRIBUTES=() ASSEMBLES=() WANTS=(); source "$f"; eval 'printf "%s\n" "${'"$2"'[@]}"' ) | sed '/^$/d'
}

# _sel_default <补丁> → on 或 off:patch.conf 的 DEFAULT 字段(不写就是 on)。只对 optional/* 有意义,
#   make-9008.sh 向导问"要吗?"时用来定默认答案。
_sel_default() {
    local f=$REPO/patches/$1/patch.conf d
    [[ -f $f ]] || { echo on; return; }
    d=$( DEFAULT=on; source "$f"; echo "$DEFAULT" )
    [[ $d == off ]] && echo off || echo on
}

# _sel_assembler <产物> → 目录里负责这个产物的补丁(ASSEMBLES 里有它)
_sel_assembler() {
    local m
    while IFS= read -r m; do
        _sel_meta "$m" ASSEMBLES | grep -qxF -- "$1" && echo "$m"
    done < <(_sel_catalog)
}

# _sel_deps <补丁> → 它需要的补丁(REQUIRES + 它登记的产物的 assemble)
_sel_deps() {
    local a
    _sel_meta "$1" REQUIRES
    for a in $(_sel_meta "$1" CONTRIBUTES); do _sel_assembler "$a"; done | grep -vxF -- "$1"   # 自己登记自己打包的不算
}

# select_check_order   按 patch.conf 核对目录(MODS)的顺序;不对就打印并返回非 0
#   REQUIRES、AFTER 要在前面;BEFORE 要在后面;登记了产物的要排在它的 assemble 前面
select_check_order() {
    local list m d a i bad=0
    for list in MODS; do
        local -n L=$list
        local -A pos=()
        for i in "${!L[@]}"; do pos[${L[i]}]=$i; done
        for m in "${L[@]}"; do
            for d in $(_sel_meta "$m" REQUIRES) $(_sel_meta "$m" AFTER); do
                [[ -n ${pos[$d]:-} ]] || continue
                (( pos[$d] < pos[$m] )) || { echo "顺序不对($list): $d 要排在 $m 前面" >&2; bad=1; }
            done
            for d in $(_sel_meta "$m" BEFORE); do
                [[ -n ${pos[$d]:-} ]] || continue
                (( pos[$d] > pos[$m] )) || { echo "顺序不对($list): $d 要排在 $m 后面" >&2; bad=1; }
            done
            for a in $(_sel_meta "$m" CONTRIBUTES); do
                for d in $(_sel_assembler "$a"); do
                    [[ -n ${pos[$d]:-} && $d != "$m" ]] || continue
                    (( pos[$d] > pos[$m] )) || { echo "顺序不对($list): $d(assemble $a)要排在 $m 后面" >&2; bad=1; }
                done
            done
        done
        unset -n L
    done
    return $bad
}

_sel_profile_file() {
    local p=$1
    if [[ -f $p ]]; then echo "$p"; return; fi
    for f in "${DEVICE_DIR:-}/profiles/$p.txt" "$REPO/profiles/$p.txt"; do
        [[ -f $f ]] && { echo "$f"; return; }
    done
    return 1
}

# 规则列表:"+x" / "-x"
_sel_rules() {
    local t l
    if [[ -n $SEL_PROFILE_FILE ]]; then
        while IFS= read -r l; do
            l=${l%%#*}; l=${l//[[:space:]]/}
            [[ -n $l ]] || continue
            [[ $l == [+-]* ]] || l=+$l
            echo "$l"
        done < "$SEL_PROFILE_FILE"
    fi
    # 相机三选一:CAMERA=zui|pixel|none。排在预设之后、WITH/WITHOUT 之前(WITH 仍可以两个都选)
    local zc=required/general/camera/zuicamera pc=required/general/camera/pixel-camera
    if [[ -n ${CAMERA:-} ]] && _sel_catalog | grep -qxF -- "$zc"; then
        case $CAMERA in
            zui)   echo "+$zc"; echo "-$pc" ;;
            pixel) echo "-$zc"; echo "+$pc" ;;
            none)  echo "-$zc"; echo "-$pc" ;;
            *) echo "CAMERA 只能是 zui、pixel、none,现在是 '$CAMERA'" >&2; return 1 ;;
        esac
    fi
    local w=${WITH:-} wo=${WITHOUT:-}
    for t in ${w//,/ }; do echo "+$t"; done
    for t in ${wo//,/ }; do echo "-$t"; done
}

select_flavor() {
    local m o= d=
    for m in "${SEL_MODS[@]}"; do
        case $m in optional/*) o=_optional ;; debug/*) d=_debug ;; esac
    done
    printf '%s%s' "$o" "$d"
}
SEL_MODS=(); SEL_NOTES=(); SEL_PROFILE_FILE=; SEL_ALL=()
select_resolve() {
    local -a sel=() removed=() rules=() hit=()
    local m r t d changed
    SEL_NOTES=(); SEL_PROFILE_FILE=
    select_check_order || return 1
    mapfile -t SEL_ALL < <(_sel_catalog)
    for m in "${SEL_ALL[@]}"; do
        _sel_in "$m" "${MODS_OFF[@]}" || sel+=("$m")
    done
    for m in "${MODS_OFF[@]}"; do
        _sel_catalog | grep -qxF -- "$m" || { echo "MODS_OFF 里的 $m 不在 MODS 里" >&2; return 1; }
    done
    if [[ -n ${PROFILE:-} ]]; then
        SEL_PROFILE_FILE=$(_sel_profile_file "$PROFILE") || { echo "找不到预设 $PROFILE(devices/<设备>/profiles/ 或 profiles/ 下的 $PROFILE.txt)" >&2; return 1; }
    fi
    local rl; rl=$(_sel_rules) || return 1
    [[ -n $rl ]] && mapfile -t rules <<< "$rl"
    for r in "${rules[@]}"; do
        t=${r:1}
        mapfile -t hit < <(_sel_match "$t")
        (( ${#hit[@]} )) || { echo "规则 '$t' 没有匹配到任何补丁(看 make list)" >&2; return 1; }
        for m in "${hit[@]}"; do
            if [[ $r == +* ]]; then
                _sel_in "$m" "${sel[@]}" || sel+=("$m")
                local -a keep=(); for d in "${removed[@]}"; do [[ $d == "$m" ]] || keep+=("$d"); done; removed=("${keep[@]}")
            else
                local -a keep=(); for d in "${sel[@]}"; do [[ $d == "$m" ]] || keep+=("$d"); done; sel=("${keep[@]}")
                [[ $t == all ]] || _sel_in "$m" "${removed[@]}" || removed+=("$m")
            fi
        done
    done
    # assemble 补丁(ASSEMBLES 非空)没人登记时原样输出产物(boot 保持原厂、APEX 不动),所以除非明确点名去掉,总是带上。
    # 这样 "-all" 从头挑时也还有 boot.img,9008 包能做。
    for m in "${SEL_ALL[@]}"; do
        [[ -n $(_sel_meta "$m" ASSEMBLES) ]] || continue
        _sel_in "$m" "${sel[@]}" "${removed[@]}" || sel+=("$m")
    done
    # WANTS(软依赖):选了它就顺带打上,除非被明确去掉;去掉了也不连累它
    for m in "${sel[@]}"; do
        for d in $(_sel_meta "$m" WANTS); do
            _sel_in "$d" "${sel[@]}" "${removed[@]}" && continue
            sel+=("$d"); SEL_NOTES+=("加上 $d($m 想要它,见 patch.conf 的 WANTS)")
        done
    done
    # 依赖:补上缺的,补不了的(被明确去掉了)就把依赖它的也去掉,直到不再变化
    changed=1
    while (( changed )); do
        changed=0
        for m in "${sel[@]}"; do
            for d in $(_sel_deps "$m" | sort -u); do
                _sel_in "$d" "${sel[@]}" && continue
                if _sel_in "$d" "${removed[@]}"; then
                    local -a keep=(); for t in "${sel[@]}"; do [[ $t == "$m" ]] || keep+=("$t"); done; sel=("${keep[@]}")
                    _sel_in "$m" "${removed[@]}" || removed+=("$m")
                    SEL_NOTES+=("去掉 $m(它要 $d,$d 被去掉了)")
                elif _sel_catalog | grep -qxF -- "$d"; then
                    sel+=("$d")
                    SEL_NOTES+=("加上 $d($m 要它)")
                else
                    echo "$m 要 $d,但 $d 不在 device.conf 的 MODS 里" >&2; return 1
                fi
                changed=1; break 2
            done
        done
    done
    SEL_MODS=()
    for m in "${MODS[@]}"; do _sel_in "$m" "${sel[@]}" && SEL_MODS+=("$m"); done
    return 0
}

# 规则的一行描述
select_desc() {
    local s=
    [[ -n ${PROFILE:-} ]] && s+="PROFILE=$PROFILE "
    [[ -n ${CAMERA:-} ]] && s+="CAMERA=$CAMERA "
    [[ -n ${WITH:-} ]] && s+="WITH=$WITH "
    [[ -n ${WITHOUT:-} ]] && s+="WITHOUT=$WITHOUT "
    echo "${s:-默认(device.conf)}"
}

select_summary() {
    local m n total=${#SEL_ALL[@]} got=${#SEL_MODS[@]}
    echo "选择: $(select_desc)"
    echo "  打 ${#SEL_MODS[@]}/${#SEL_ALL[@]} 个补丁"
    if (( got * 2 < total )); then
        for m in "${SEL_MODS[@]}"; do echo "  打 $m"; done
    else
        for m in "${SEL_ALL[@]}"; do
            if _sel_in "$m" "${SEL_MODS[@]}"; then
                _sel_in "$m" "${MODS_OFF[@]}" && echo "  + $m(默认不打,这次打)"
            else
                _sel_in "$m" "${MODS_OFF[@]}" || echo "  - $m"
            fi
        done
    fi
    for n in "${SEL_NOTES[@]}"; do echo "  依赖: $n"; done
}

select_record() {
    {
        echo "# 这次构建的补丁选择(toolkit/lib/select.sh 生成)"
        echo "rules: $(select_desc)"
        [[ -n $SEL_PROFILE_FILE ]] && { echo "profile: $SEL_PROFILE_FILE"; sed 's/^/  | /' "$SEL_PROFILE_FILE"; }
        local x
        for x in "${SEL_NOTES[@]}"; do echo "note: $x"; done
        for x in "${SEL_MODS[@]}"; do
            local v; v=$(sed -n 's/^VERSION=//p' "$REPO/patches/$x/patch.conf" 2>/dev/null | head -1)
            echo "patch: $x@${v:-?}"
        done
    } > "$1"
}
