#!/usr/bin/env bash
# video-freeze-fix:视频画面卡住修复(X 等 app 刷视频时声音继续、画面定格,拖进度条恢复)。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md 和 gsi-codec2-video-freeze-guide 的 doc/research.md。
run_parts
