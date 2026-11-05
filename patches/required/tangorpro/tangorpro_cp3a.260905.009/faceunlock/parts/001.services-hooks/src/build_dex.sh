#!/usr/bin/env bash
# 从当前底包的 system 现取 classpath,编出 Sense 框架类的 dex(进 services.jar 当 classes4.dex)。
# apply.sh 在构建时调它;也可以单独跑来核对产物。
#
# 用法: build_dex.sh <底包 system 目录> <输出 dex 路径>
# 需要的工具(环境变量):
#   JAVA_HOME  JDK 17(默认 /usr/lib/jvm/java-17-openjdk-amd64)
#   D2J        dex2jar 2.4.38 的 d2j-dex2jar.sh(github.com/ThexXTURBOXx/dex2jar)
#   R8         r8.jar(含 D8;8.5.35 和 8.13 都能编出一致结果,见 README)
#
# 做的事:dex2jar 把底包 framework.jar / services.jar / core-libart.jar(ART apex 里)转成 class jar 当
# classpath → javac 编 java/(KLC 补丁适配类 + SenseHooks 等新类 + AIDL 生成的 Java)→ d8(必须 desugar)
# 成一个 classes.dex → check_dex.py 查 ART 运行期会崩的 dex 问题。
set -euo pipefail

SYS=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
: "${JAVA_HOME:=/usr/lib/jvm/java-17-openjdk-amd64}" "${D2J:?缺 D2J}" "${R8:?缺 R8}" "${APKTOOL:?缺 APKTOOL(给 check_dex.py 用)}"
command -v debugfs >/dev/null || { echo "缺 debugfs(e2fsprogs),用来从 ART apex 取 core-libart.jar" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cp" "$T/classes" "$T/dex" "$(dirname "$OUT")"

echo "==== classpath(从底包现取)"
sudo cat "$SYS/framework/framework.jar" > "$T/framework.jar"
sudo cat "$SYS/framework/services.jar"  > "$T/services.jar"
"$D2J" -f -o "$T/cp/framework.jar" "$T/framework.jar" >/dev/null
"$D2J" -f -o "$T/cp/services.jar"  "$T/services.jar"  >/dev/null
# core-libart.jar 在 ART apex 的 payload(ext4)里。不 mount,用 unzip + debugfs dump 取出来。
# A17 的 ART apex 是压缩格式 .capex(内含 original_apex),bp1a/ap3a 是 .apex;两种都找、都认。
ART_APEX=$(sudo bash -c 'for f in "$1"/apex/com.google.android.art.capex "$1"/apex/com.google.android.art.apex; do [ -e "$f" ] && { echo "$f"; break; }; done' _ "$SYS")
[[ -n $ART_APEX ]] || { echo "找不到 ART apex(com.google.android.art.{capex,apex})" >&2; exit 1; }
sudo cat "$ART_APEX" > "$T/art.apex"
( cd "$T"
  if unzip -l art.apex 2>/dev/null | grep -q original_apex; then
      unzip -q -o art.apex original_apex && unzip -q -o original_apex apex_payload.img   # 压缩 APEX:内层才是 payload
  else
      unzip -q -o art.apex apex_payload.img                                              # 未压缩 APEX:直接有 payload
  fi )
debugfs -R "dump /javalib/core-libart.jar $T/core-libart.jar" "$T/apex_payload.img" 2>/dev/null
[[ -s $T/core-libart.jar ]] || { echo "从 ART apex 取 core-libart.jar 失败" >&2; exit 1; }
"$D2J" -f -o "$T/cp/core-libart.jar" "$T/core-libart.jar" >/dev/null

echo "==== javac + d8"
"$JAVA_HOME/bin/javac" -nowarn -encoding UTF-8 --release 17 -proc:none -d "$T/classes" \
    -cp "$T/cp/framework.jar:$T/cp/services.jar:$T/cp/core-libart.jar" $(find "$HERE/java" -name '*.java')
(cd "$T/classes" && "$JAVA_HOME/bin/jar" cf "$T/sense.jar" .)
# 必须 desugar:javac 17 对 private 方法引用会编成 invoke-custom,不 desugar 时 ART 抛 IncompatibleClassChangeError(V1 实机崩)
java -cp "$R8" com.android.tools.r8.D8 --release --min-api 35 \
    --lib "$JAVA_HOME" --lib "$T/cp/core-libart.jar" --lib "$T/cp/framework.jar" --classpath "$T/cp/services.jar" \
    --output "$T/dex" "$T/sense.jar"
APKTOOL="$APKTOOL" python3 -I "$HERE/check_dex.py" "$T/dex/classes.dex"
cp "$T/dex/classes.dex" "$OUT"
echo "==== classes4.dex: $(sha256sum "$OUT" | cut -c1-16)  $OUT"
