# identity:机型身份:ro.product.* 改成 TB321FU、指纹和 build 描述符从原厂固件现取、ro.build.display.id 写版本号。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
