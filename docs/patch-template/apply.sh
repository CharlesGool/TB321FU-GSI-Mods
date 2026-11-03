# 补丁入口。被 source 进已加载 toolkit/lib/common.sh 的 bash(set -euo pipefail),环境变量和 put/put_dir 等见 docs/MODULE-SPEC.md。
# REQUIRES 里写了什么,这里就 require_mod 什么。
require_mod required/general/herald-core

# 单文件补丁:直接写在这里。
# put "$MOD/files/xxx.sh" etc/herald_payload/plugins/xxx.sh 0755 0:0 u:object_r:herald_exec:s0

# 合并补丁(内部分几部分):把下面这行留着,把部分放进 parts/NNN.<名字>/,按编号顺序跑;没有 parts/ 就删掉它。
run_parts
