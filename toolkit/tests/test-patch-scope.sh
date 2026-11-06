#!/usr/bin/env bash
# runmods.sh 的适用范围检查 scope_ok:required/general 全跑;required/<前缀>/ 和嵌套的更窄范围按底包 ID 命中才跑。
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$REPO/toolkit/lib/runmods.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; BUILD_STATE=$T
pass=0; fail=0
chk() { local want=$1 id=$2 m=$3; [[ -n $id ]] && echo "$id" > "$T/base-id" || rm -f "$T/base-id"
        scope_ok "$m"; local got=$?; if [[ $got == "$want" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: id='$id' $m 期望 $want 得到 $got"; fi; }
A=tangorpro_ap3a.241005.015_12366759
chk 0 $A required/general/bug-fix/identity
chk 0 $A required/tangorpro/rotation-fix
chk 0 $A required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix
chk 0 $A required/general/battery
chk 0 $A debug/herald-ush
B=tangorpro_bp1a.250505.005_1
chk 0 $B required/tangorpro/rotation-fix
chk 1 $B required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix
C=shiba_bp1a.250505.005_1
chk 1 $C required/tangorpro/rotation-fix
chk 0 $C required/general/bug-fix/identity
chk 0 "" required/tangorpro/rotation-fix
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
