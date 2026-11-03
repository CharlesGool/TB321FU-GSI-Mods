# phh 的 rw-system.sh 会把 vendor 的相机库复制到 tmpfs、sed 改属性名再 bind 回 /vendor。
# TB321FU 的这些库里没有要改的字符串,结果只是多出一个可写 tmpfs 挂载。补一行:文件里没有那几个字符串就跳过。
if sudo test -f "$SYS/system/bin/rw-system.sh"; then
    edit system/bin/rw-system.sh python3 -I "$MOD/fix_rw_system.py"
else
    log "(底包没有 phh 的 rw-system.sh,跳过)"
fi
