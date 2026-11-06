# slim/pixel-hardware:按 lists/ 里的清单删东西。精简脚本是通用的(toolkit/lib/removelist.sh 的 slim_apply),删什么由本补丁自己的 lists/*.list 决定。
source "$TOOLKIT/lib/removelist.sh"
slim_apply "$MOD/lists"
