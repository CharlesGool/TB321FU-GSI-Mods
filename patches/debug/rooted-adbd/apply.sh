# adb root:让 adbd 能按需切成 root,并且 root 之后的 shell 不被 SELinux 拦。和 adb-on-boot 互不依赖:
# 这里不碰 persist.sys.usb.config(开机开 ADB)和 ro.adb.secure(免授权),也不碰 ro.secure(adbd 开机仍是 shell 用户,要 root 时手动 adb root)。
need_file build.prop
need_file etc/selinux/plat_sepolicy.cil
# 1. adbd 只有在 ro.debuggable=1 时才肯响应 adb root(user 版出厂是 0)。debug-off 把 Mystic 的调试段删了,这里排在它后面再加回来。
prop build.prop ro.debuggable 1 --add
sudo grep -qxF 'ro.debuggable=1' "$SYS/build.prop" || die "ro.debuggable 没改成 1"
# 2. 光 uid 0 不够:user 版策略下 adbd/shell 域仍受限(读不了的路径还是读不了)。把这两个域设成 permissive,AVC 照常记、不拦。
cil_append "debug/rooted-adbd: adbd、shell 域 permissive" "$MOD/rooted_adbd.cil"
log "完成: ro.debuggable=1,adbd/shell permissive"
