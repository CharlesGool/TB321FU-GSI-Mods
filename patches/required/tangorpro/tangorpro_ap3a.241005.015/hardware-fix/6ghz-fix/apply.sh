# 6ghz-fix:6GHz 热点修复。国家码默认 DE(驱动才允许 6GHz 当 AP)+ 设置里选 6GHz 时把热点固定在 6GHz 频段。
# 两个部分都只往 wifi-apex-assemble 登记 smali 补丁,自己不动 APEX。
# 合并补丁:各部分在 parts/NNN.<部分>/,按编号顺序跑(toolkit/lib/common.sh 的 run_parts)。原理见各部分的 README.md。
run_parts
