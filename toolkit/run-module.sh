#!/usr/bin/env bash
# 单独跑一个补丁(开发和调试用),环境和 toolkit/build.sh 里一样。
#
# 用法: toolkit/run-module.sh <device.conf> <工作树根> <补丁名> [临时目录]
#   工作树根下要有 system/。调试时可以只拷需要的文件做个小树:
#     sudo mkdir -p /tmp/t && sudo cp -a --parents /mnt/base/./system/framework/services.jar /tmp/t/
# 环境变量:
#   RAN="herald-core"   假装这些模块已经跑过(满足 require_mod);同一个临时目录连着跑多个模块时,
#                                              前面跑过的会自动记录,不用再写
#   同一个临时目录连着跑,登记(contrib)也会累积,可以先跑几个贡献者再跑 assemble
set -euo pipefail
CONF=$(realpath "$1"); TREE=$(realpath "$2"); m=$3
TOOLKIT=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$TOOLKIT"); DEVICE_DIR=$(dirname "$CONF")
WORKROOT=${4:-$(mktemp -d)}; WORK=$WORKROOT/$m; mkdir -p "$WORK"
FW_OUT=${FW_OUT:-$WORKROOT/firmware}; mkdir -p "$FW_OUT"      # 改 boot 的补丁往这里写 boot.img
BUILD_STATE=$WORKROOT/.state; mkdir -p "$BUILD_STATE/ran"
RAN=${RAN:-}; for r in ${RAN//,/ }; do touch "$BUILD_STATE/ran/${r//\//__}"; done
export CONF TREE SYS=$TREE/system FW_OUT TOOLKIT REPO DEVICE_DIR BUILD_STATE MOD=$REPO/patches/$m MOD_NAME=$m WORK
bash -c 'set -a; source "$CONF"; set +a; source "$TOOLKIT/lib/common.sh"; source "$MOD/apply.sh"; :'
touch "$BUILD_STATE/ran/${m//\//__}"
