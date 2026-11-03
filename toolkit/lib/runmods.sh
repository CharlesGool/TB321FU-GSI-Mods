# 按顺序跑一串补丁。toolkit/build.sh、tests/test-modules.sh 用。
#
# 用之前要有这些变量: CONF REPO TOOLKIT BUILD_STATE,以及 step() 函数。
# 可选环境变量:
#   ONLY=a,b/c    只跑这些。可以写整组(wifi)或单个模块(wifi-country-code),调试用,出来的镜像不能刷
#   SURVEY=1      模块失败不停,跑完全部再汇总(换底包摸底用);汇总后返回非 0

# run_mods <输出目录> <补丁名>...    补丁名是 patches/ 下的相对路径(如 battery/charge-limit),对应 patches/<补丁名>/apply.sh
#   每个补丁的日志在 <输出目录>/logs/<补丁名把 / 换成 __>.log,临时目录 <输出目录>/work/<补丁名>
#   失败的模块名追加进全局数组 FAILED。
FAILED=()

# scope_ok <补丁名>   required/<范围>/… 下的补丁只在底包 ID 命中范围时才跑。
#   范围 = required/ 下第一层文件夹(general 除外,它对所有底包生效);第二层文件夹若以"<第一层>_"开头,是更窄的范围
#   (required/tangorpro/tangorpro_ap3a.241005.015/…)。范围名是底包 ID 的前缀(按 _ 分段),和 slim 清单的范围同一套规则。
#   底包 ID 取 $BUILD_STATE/base-id(toolkit/build.sh 记的);没有就不拦(单独调试时)。
SCOPE_SKIP=
scope_ok() {
    local m=$1 id seg s
    SCOPE_SKIP=
    [[ $m == required/* ]] || return 0
    [[ -f $BUILD_STATE/base-id ]] || return 0
    id=$(cat "$BUILD_STATE/base-id")
    IFS=/ read -ra seg <<< "$m"
    [[ ${seg[1]} == general ]] && return 0
    for s in "${seg[1]}" "${seg[2]:-}"; do
        [[ -n $s ]] || continue
        [[ $s == "${seg[1]}" || $s == "${seg[1]}"_* ]] || continue
        if [[ $id != "$s" && $id != "$s"_* ]]; then SCOPE_SKIP="底包 ID $id 不在适用范围 $s"; return 1; fi
    done
    return 0
}
run_mods() {
    local out=$1; shift
    local m safe
    mkdir -p "$out/logs" "$BUILD_STATE/ran"
    for m in "$@"; do
        if [[ -n ${ONLY:-} && ,$ONLY, != *,$m,* && ,$ONLY, != *,${m%%/*},* ]]; then echo "(跳过 $m)"; continue; fi
        safe=${m//\//__}
        if ! scope_ok "$m"; then step "模块 $m"; echo "(跳过 $m:$SCOPE_SKIP)"; continue; fi
        step "模块 $m"
        mkdir -p "$out/work/$m"
        # 每个模块在子 shell 里跑:拿到 device.conf 的全部变量和 common.sh 的函数
        # 配置在模块自己的 shell 里读(数组变量没法 export,放在外面读模块就看不到)
        if ( export CONF MOD=$REPO/patches/$m MOD_NAME=$m WORK=$out/work/$m
             bash -c 'set -a; source "$CONF"; set +a; source "$TOOLKIT/lib/common.sh"; source "$MOD/apply.sh"; :' ) 2>&1 | tee "$out/logs/$safe.log" \
           && [[ ${PIPESTATUS[0]} == 0 ]]; then
            touch "$BUILD_STATE/ran/$safe"
        else
            echo "模块 $m 失败,日志 $out/logs/$safe.log"
            # SURVEY=1:失败的模块记下来继续跑后面的(依赖失败模块的会跟着失败,看日志区分)
            [[ ${SURVEY:-0} == 1 ]] || exit 1
            FAILED+=("$m")
        fi
    done
}

# check_modules <模块名>...    开跑前检查每个模块都存在且可执行
check_modules() {
    local m
    for m in "$@"; do
        [[ -x $REPO/patches/$m/apply.sh ]] || { echo "缺补丁或不可执行: patches/$m/apply.sh"; return 1; }
    done
}

# check_contribs    收尾检查:有模块往某个产物贡献了东西,但没有对应的 assemble 模块把它们用掉
check_contribs() {
    local d bad=0
    for d in "$BUILD_STATE"/contrib/*/; do
        [[ -d $d ]] || continue
        if [[ ! -f $d/.consumed ]]; then
            echo "错误: 产物 $(basename "$d") 收到了贡献但没有 assemble 模块处理它:"
            ls "$d" | grep -v '\.marker$' | sed 's/^/    /'
            echo "      把负责这个产物的 assemble 补丁加进 MODS(排在贡献者后面)。"
            bad=1
        fi
    done
    return $bad
}
