# slim/now-playing:删 Now Playing(常驻占录音会话 → 音频断续)。删什么见 lists/now-playing.list。
# 精简脚本通用(toolkit/lib/removelist.sh 的 slim_apply),删不到只记日志不算失败。
source "$TOOLKIT/lib/removelist.sh"
slim_apply "$MOD/lists"
