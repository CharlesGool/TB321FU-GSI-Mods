# 按清单删文件/目录。由模块的 apply.sh / part.sh 自己 source(不属于 common.sh):
#     source "$TOOLKIT/lib/removelist.sh"
#     remove_list "$MOD/remove.txt"          # 一个清单
#     slim_apply "$MOD/lists"                # 一个清单目录(精简补丁用)
#
# remove_list <清单文件> [--require-any]
#   清单每行一个路径,相对镜像里的 system/;空行和 # 开头的行忽略。
#   路径里可以带通配符 * ? [],按 system/ 下展开,所以带版本号的名字写成 CalculatorGooglePrebuilt_* 就行;
#   展开不到的条目记为"底包里没有"(不是错误)。不允许 / 开头和 ..。
#   最后 log 一行"清单 N 项,删了 M 项,底包里没有 K 项",并逐条列出没有的项,方便维护清单。
#   --require-any:一项都没删到就 die(用于"底包必须有这些东西"的场合);默认删不到只 log。
#
# base_id
#   这份底包的唯一 ID:<产品>_<构建号>_<增量号>,全小写,取自底包 ro.system.build.fingerprint
#   (google/tangorpro/tangorpro:15/AP3A.241005.015/12366759:... → tangorpro_ap3a.241005.015_12366759)。
#   toolkit/build.sh 在 identity 改指纹之前就记到 $BUILD_STATE/base-id;单独跑补丁时现读 system/build.prop。
#
# slim_apply <清单目录>
#   通用精简脚本:把目录里每个 *.list 按文件名顺序交给 remove_list。删什么由各补丁自己的 lists/ 决定,
#   补丁的 apply.sh 就两行(source 本文件 + slim_apply "$MOD/lists")。适用范围(哪些底包要跑)由补丁所在的文件夹决定
#   (required/<底包前缀>/…,见 toolkit/lib/runmods.sh 的 scope_ok),不在这里判断。
base_id() {
    local f
    # 显式覆盖(device.conf 里设 BASE_ID):底包指纹被 GSI 工具泛化(如新版 MysticGSI 把 product 改成
    # generic_system_google)时,用它声明这台机器真正的底包 ID,让版本门控(required/<前缀>/…)正常命中。
    if [[ -n ${BASE_ID:-} ]]; then printf '%s\n' "${BASE_ID,,}"; return; fi
    if [[ -s ${BUILD_STATE:-/nonexistent}/base-id ]]; then cat "$BUILD_STATE/base-id"; return; fi
    f=$(sudo grep -h '^ro.system.build.fingerprint=' "$SYS/build.prop" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    [[ -n $f ]] || f=$(sudo grep -h '^ro.build.fingerprint=' "$SYS/build.prop" 2>/dev/null | tail -1 | cut -d= -f2- || true)
    IFS=/ read -r _ prod _ bid inc _ <<< "$f"
    [[ -n ${prod:-} && -n ${bid:-} && -n ${inc:-} ]] || die "认不出底包 ID:指纹是 '$f'"
    printf '%s_%s_%s\n' "$prod" "$bid" "${inc%%:*}" | tr 'A-Z' 'a-z'
}

remove_list() {
    local list=$1 require=${2:-} total=0 gone=0 p hits f missing=()
    [[ -f $list ]] || die "清单文件不存在: $list"
    while IFS= read -r p || [[ -n $p ]]; do
        p=${p%%#*}; p=${p//[[:space:]]/}
        [[ -z $p ]] && continue
        [[ $p == /* || $p == *..* ]] && die "清单 $(basename "$list") 里的路径不合法: $p"
        total=$((total + 1))
        hits=0
        if [[ $p == *[\*\?\[]* ]]; then
            while IFS= read -r -d '' f; do
                remove "$f"; gone=$((gone + REMOVED)); hits=$((hits + REMOVED))
            done < <(sudo bash -c 'cd "$1" && shopt -s nullglob dotglob && for f in $2; do printf "%s\0" "$f"; done' _ "$SYS" "$p")
        else
            remove "$p"; gone=$((gone + REMOVED)); hits=$REMOVED
        fi
        (( hits )) || missing+=("$p")
    done < "$list"
    log "清单 $(basename "$list"): $total 项,删了 $gone 个文件/目录,底包里没有 ${#missing[@]} 项"
    for p in "${missing[@]}"; do log "  (没有) $p"; done
    if [[ $require == --require-any ]] && (( gone == 0 )); then
        die "一项都没删到:底包的目录结构和预期不一样,检查 $(basename "$list") 的路径"
    fi
}

slim_apply() {
    local dir=$1 l n=0
    [[ -d $dir ]] || die "清单目录不存在: $dir"
    log "底包 ID: $(base_id)"
    for l in "$dir"/*.list; do
        [[ -f $l ]] || continue
        n=$((n + 1)); remove_list "$l"
    done
    (( n )) || die "$dir 里一份 .list 都没有"
}
