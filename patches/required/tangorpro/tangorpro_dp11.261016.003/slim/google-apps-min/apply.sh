# slim/google-apps-min:按 lists/ 删指定的 8 个 Google 应用(DP11 专属最小精简)。
# 精简脚本通用(toolkit/lib/removelist.sh 的 slim_apply),删什么由本补丁 lists/*.list 决定。
source "$TOOLKIT/lib/removelist.sh"
slim_apply "$MOD/lists"
