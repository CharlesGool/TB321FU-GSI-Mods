# custom-font:自定义系统字体:SystemFonts 改读 /data/fonts/herald/ 的字体包(不挂载、不占 system)+ heraldctl 装包/选用/撤回。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
require_mod required/general/herald-core
run_parts
