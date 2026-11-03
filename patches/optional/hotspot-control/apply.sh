# hotspot-control:热点控制:热点名称/密码/加密/频段等自定义(herald_ap_*)+ heraldctl wifi|hotspot 命令。
# 自定义部分只往 wifi-apex-assemble 登记 smali 补丁;命令部分接入 herald-core,没选核心时跳过。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
