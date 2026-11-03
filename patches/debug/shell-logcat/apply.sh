# Enforcing 下 adb shell 跑 logcat 被拒(Mystic 的策略没给 shell 执行 logd_exec),补一条 allow。
cil_append "selinux/shell-logcat: shell 执行 logcat" "$MOD/shell_logcat.cil"
