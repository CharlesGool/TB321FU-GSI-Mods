#!/usr/bin/env bash
# 模块独立性测试:证明"每个模块都能单独打、任意子集都能构建"。
#
# 用法: toolkit/tests/test-modules.sh <device.conf> [--solo|--leave-out|--both] [补丁名 ...]
#   --solo       (默认)每个模块各自在一棵干净底包上单独跑。需要别人才能跑的会自动带上:
#                  - 脚本里 require_mod X 的 X(控制后端 herald-core)
#                  - 往某个产物 contrib_add 的模块,带上负责这个产物的 assemble 模块
#   --leave-out  每个模块各挑出一次:跑"MODS 去掉它(以及必须依赖它的模块)"的全部。慢,但能证明剩下的不依赖它。
#   --both       两个都跑
#   后面可以列补丁名,只测这几个;不列就测这次选择(默认 device.conf,PROFILE/WITH/WITHOUT 可改)的全部 system 补丁。
# 环境变量: OUT=<目录>  日志和临时文件位置(默认临时目录);KEEP=1 不删日志
#
# 做法:把 BASE_GSI 只读挂载,每次测试在它上面叠一层 overlayfs(upper 在临时目录),模块改的东西都落在 upper,
# 测完卸载删掉,所以每个测试都是干净底包、而且不用复制几个 GB。需要 sudo。
# 改 boot 的补丁也一起测:每个测试给一个空的固件目录(FW_OUT),里面放原厂 init_boot / vendor_boot。
set -euo pipefail

CONF=$(realpath "$1"); shift
MODE=solo
case "${1:-}" in --solo|--leave-out|--both) MODE=${1#--}; shift;; esac
ONLY_LIST=("$@")
TOOLKIT=$(cd "$(dirname "$0")/.." && pwd); REPO=$(dirname "$TOOLKIT"); DEVICE_DIR=$(dirname "$CONF")
export REPO
# shellcheck disable=SC1090
source "$CONF"
source "$TOOLKIT/lib/select.sh"
select_resolve || exit 1
MODS=("${SEL_MODS[@]}")    # 测的是这次的选择(默认 = device.conf;PROFILE/WITH/WITHOUT 可改)
: "${BASE_GSI:?}"; [[ -f $BASE_GSI ]] || { echo "底包不存在: $BASE_GSI"; exit 1; }
ROOT=${OUT:-$(mktemp -d)}; mkdir -p "$ROOT/logs"
LOW=$ROOT/low
step() { echo "---- $*"; }
source "$TOOLKIT/lib/runmods.sh"

cleanup() { mountpoint -q "$ROOT/m" 2>/dev/null && sudo umount "$ROOT/m"; mountpoint -q "$LOW" 2>/dev/null && sudo umount "$LOW"
            sudo rm -rf "$ROOT/u" "$ROOT/w" "$ROOT/m" "$ROOT/state" "$ROOT/out" 2>/dev/null || true
            [[ ${KEEP:-0} == 1 ]] || { sudo rm -rf "$LOW" "$ROOT/logs" 2>/dev/null; rmdir "$ROOT" 2>/dev/null || true; }; }
trap cleanup EXIT
mkdir -p "$LOW"; sudo mount -o loop,ro "$BASE_GSI" "$LOW"

# ---- 依赖(读 patch.conf,和构建时一样:REQUIRES + 登记产物的 assemble)----
mod_deps() { _sel_deps "$1" | sort -u; }
in_mods() { local m; for m in "${MODS[@]}"; do [[ $m == "$1" ]] && return 0; done; return 1; }

# solo_set <模块> → 需要一起跑的集合(按 MODS 顺序输出)
solo_set() {
    local want=("$1") i=0 m r a x
    while (( i < ${#want[@]} )); do
        m=${want[i]}; i=$((i+1))
        for r in $(mod_deps "$m"); do [[ " ${want[*]} " == *" $r "* ]] || want+=("$r"); done
    done
    for m in "${MODS[@]}"; do if [[ " ${want[*]} " == *" $m "* ]]; then echo "$m"; fi; done
}
# leave_set <模块> → MODS 去掉它和(传递地)必须依赖它的模块
leave_set() {
    local gone=("$1") changed=1 m r
    while (( changed )); do changed=0
        for m in "${MODS[@]}"; do [[ " ${gone[*]} " == *" $m "* ]] && continue
            for r in $(mod_deps "$m"); do [[ " ${gone[*]} " == *" $r "* ]] && { gone+=("$m"); changed=1; break; }; done; done; done
    for m in "${MODS[@]}"; do [[ " ${gone[*]} " == *" $m "* ]] || echo "$m"; done
}

# run_test <名字> <模块...>   返回 0 = 通过
run_test() {
    local name=$1; shift
    local safe=${name//\//__}
    sudo rm -rf "$ROOT/u" "$ROOT/w" "$ROOT/m" "$ROOT/state" "$ROOT/out"; mkdir -p "$ROOT/u" "$ROOT/w" "$ROOT/m" "$ROOT/state" "$ROOT/out"
    sudo mount -t overlay overlay -o "lowerdir=$LOW,upperdir=$ROOT/u,workdir=$ROOT/w" "$ROOT/m"
    local rc=0
    sudo rm -rf "$ROOT/fw"; mkdir -p "$ROOT/fw"
    (   export TREE=$ROOT/m SYS=$ROOT/m/system FW_OUT=$ROOT/fw TOOLKIT REPO DEVICE_DIR CONF BUILD_STATE=$ROOT/state VERSION
        FAILED=()
        run_mods "$ROOT/out" "$@" && check_contribs ) > "$ROOT/logs/$safe.log" 2>&1 || rc=$?
    sudo umount "$ROOT/m"
    return $rc
}

declare -a RESULTS=(); FAIL=0
report() { RESULTS+=("$1"); [[ $1 == PASS* ]] || FAIL=$((FAIL+1)); echo "$1"; }

targets=("${ONLY_LIST[@]}"); (( ${#targets[@]} )) || targets=("${MODS[@]}")
for t in "${targets[@]}"; do in_mods "$t" || { echo "$t 不在 device.conf 的 MODS 里"; exit 1; }; done

if [[ $MODE == solo || $MODE == both ]]; then
    echo "==== 单独跑(每个模块一棵干净底包)"
    for t in "${targets[@]}"; do
        set_=($(solo_set "$t"))
        if run_test "solo:$t" "${set_[@]}"; then report "PASS  solo      $t  [${set_[*]}]"
        else report "FAIL  solo      $t  [${set_[*]}]  日志 $ROOT/logs/solo:${t//\//__}.log"; fi
    done
fi
if [[ $MODE == leave-out || $MODE == both ]]; then
    echo "==== 去掉一个(跑剩下的全部)"
    for t in "${targets[@]}"; do
        set_=($(leave_set "$t"))
        if run_test "leave:$t" "${set_[@]}"; then report "PASS  leave-out $t  (跑了 ${#set_[@]} 个)"
        else report "FAIL  leave-out $t  (跑了 ${#set_[@]} 个)  日志 $ROOT/logs/leave:${t//\//__}.log"; fi
    done
fi

echo; echo "==== 汇总:${#RESULTS[@]} 项,失败 $FAIL"
if (( FAIL )); then KEEP=1; echo "失败的日志在 $ROOT/logs/"; exit 1; fi
