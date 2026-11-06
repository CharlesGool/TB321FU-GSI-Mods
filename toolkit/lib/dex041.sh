# DEX 041 容器 → 标准 multidex(v039)。改 framework/services 等 jar 的模块在"现取 jar"之后调用。
# 原理和格式说明见 dex041.py。非 041 的 jar 原样复制,所以 A15 各底包(ap3a/bp1a)完全不受影响。
#
#   undex041_jar <输入jar> <输出jar>
#
# 需要 R8 ≥ 9(D8 9.5.29 实测可以;build-tools 35 自带的 D8 8.6.2 不认 041):
#   DEX041_R8   r8.jar 路径(device.conf 里设,来源 dl.google.com/android/maven2/com/android/tools/r8/)
# 依赖 common.sh 的 die/log(模块环境里已 source);单独用时自带兜底。
type die >/dev/null 2>&1 || die() { echo "错误: $*" >&2; exit 1; }
type log >/dev/null 2>&1 || log() { echo "$*"; }

undex041_jar() {
    local in=$1 out=$2 here t
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if ! python3 -I "$here/dex041.py" check "$in"; then
        [[ $in -ef $out ]] || cp -f "$in" "$out"
        return 0
    fi
    [[ -n ${DEX041_R8:-} && -f ${DEX041_R8:-} ]] \
        || die "$(basename "$in") 的 classes.dex 是 DEX 041 容器,要 R8 ≥ 9 转成标准 dex:device.conf 设 DEX041_R8(现在: ${DEX041_R8:-未设置})"
    t=$(mktemp -d -p "${WORK:-/tmp}")
    # --min-api 36:041 只允许在 ≥36 时读;输出仍是标准 v039 多 dex。默认 debug 模式,保留调试信息(行号)。
    java -Xmx8g -cp "$DEX041_R8" com.android.tools.r8.D8 --no-desugaring --min-api 36 --output "$t" "$in" \
        >"$t.log" 2>&1 || { cat "$t.log" >&2; die "D8 转换 $(basename "$in") 失败"; }
    # 先写临时文件再 mv:允许输入输出同一路径(原地转换)
    python3 -I "$here/dex041.py" repack "$in" "$t" "$t.jar" || die "重新打包 $(basename "$in") 失败"
    mv -f "$t.jar" "$out"
    rm -rf "$t" "$t.log"
}
