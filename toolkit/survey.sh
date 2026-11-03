#!/usr/bin/env bash
# 换底包摸底:在一个新的 GSI 底包上把每个补丁单独跑一遍(带上它的依赖),出一份兼容性报告。
#
# 用法: toolkit/survey.sh <device.conf> <新底包.img> [输出目录]   (要 sudo;选择规则 PROFILE/WITH/WITHOUT 照常认)
#   输出目录(默认 out/survey-<底包文件名>/)里:
#     report.md      每个补丁:能用 / 不能用 / 因为依赖不能用,不能用的附上补丁自己报的原因(die 的那一行)
#     profile.txt    建议预设:把不能用的去掉。看过 report.md 再决定要不要用(cp 到 devices/<设备>/profiles/)
#     logs/          每个补丁的完整日志
#
# 改 boot 的补丁也会跑一遍,但它们只跟原厂固件有关,换 GSI 不影响结果。
# 原理:补丁都按"先检查前提,不满足就 die 说明原因"写(docs/MODULE-SPEC.md「换底包时的行为」),
# 所以"单独跑能过"基本就是"这个底包上能用"。能过但功能不对的(比如属性名在新版本改了)还得上真机看。
set -euo pipefail
[[ $# -ge 2 ]] || { sed -n '2,13p' "$0"; exit 1; }
CONF=$(realpath "$1"); NEW=$(realpath "$2")
TOOLKIT=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$TOOLKIT")
[[ -f $NEW ]] || { echo "底包不存在: $NEW"; exit 1; }
name=$(basename "$NEW" .img)
OUTD=$(realpath -m "${3:-$REPO/out/survey-$name}")
rm -rf "$OUTD"; mkdir -p "$OUTD"

echo "==== 在 $name 上单独跑每个补丁(慢,一个补丁一棵干净底包)"
set +e
BASE_GSI=$NEW OUT=$OUTD/run KEEP=1 "$TOOLKIT/tests/test-modules.sh" "$CONF" --solo 2>&1 | tee "$OUTD/run.txt"
set -e
mv "$OUTD/run/logs" "$OUTD/logs" 2>/dev/null || true; rm -rf "$OUTD/run"

ok=() badl=()
{
    echo "# 底包兼容性:$name"
    echo
    echo "- 底包: \`$NEW\`(sha256 \`$(sha256sum "$NEW" | cut -c1-16)…\`)"
    echo "- 配置: \`${CONF#$REPO/}\`,选择: ${PROFILE:+PROFILE=$PROFILE }${WITH:+WITH=$WITH }${WITHOUT:+WITHOUT=$WITHOUT}"
    echo "- 时间: $(date '+%F %T')"
    echo
    echo "| 补丁 | 结果 | 原因 |"
    echo "|---|---|---|"
    while IFS= read -r l; do
        [[ $l =~ ^(PASS|FAIL)\ +solo\ +([^ ]+)\ +\[([^]]*)\] ]] || continue
        res=${BASH_REMATCH[1]} p=${BASH_REMATCH[2]} set_=${BASH_REMATCH[3]}
        if [[ $res == PASS ]]; then echo "| $p | 能用 | |"; ok+=("$p"); continue; fi
        log=$OUTD/logs/solo:${p//\//__}.log
        # 哪个补丁先失败的:日志里最后一个"---- 模块 X"
        first=$(grep -o '^---- 模块 [^ ]*' "$log" 2>/dev/null | tail -1 | awk '{print $3}')
        why=$(grep -m1 '错误:' "$log" 2>/dev/null | sed 's/^ *\[[^]]*\] 错误: //; s/|/\\|/g' | cut -c1-200)
        if [[ -n $first && $first != "$p" ]]; then
            echo "| $p | 依赖不能用 | 先失败的是 $first:${why:-看日志} |"
        else
            echo "| $p | **不能用** | ${why:-看日志 logs/solo:${p//\//__}.log} |"
        fi
        badl+=("$p")
    done < "$OUTD/run.txt"
    echo
    echo "能用 ${#ok[@]} 个,不能用 ${#badl[@]} 个。"
} > "$OUTD/report.md"
{
    echo "# 在 $name 上摸底不能用的补丁($(date +%F),toolkit/survey.sh 生成)。看过 report.md 再用"
    for p in "${badl[@]}"; do echo "-$p"; done
} > "$OUTD/profile.txt"

echo; echo "==== 报告: $OUTD/report.md"; tail -1 "$OUTD/report.md"
echo "     建议预设: $OUTD/profile.txt"
