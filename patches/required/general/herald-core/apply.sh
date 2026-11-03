# 免 root 核心:herald 域里的 broker(命令通道 + 配对 + 插件接口)和无特权的命令行前端 heraldctl。
# 它不带任何具体功能:keymint 引擎、Wi-Fi 热点、电池、性能…都是别的补丁往它的插件目录里装文件接入(接口见 README)。
need_input HERALD_PAYLOAD      # 私有 payload 目录;核心只用其中的 bin/resetprop,其余是 attestation-fix 的
[[ -f $HERALD_PAYLOAD/bin/resetprop ]] || die "herald payload 缺 bin/resetprop($HERALD_PAYLOAD)"
need_file etc/selinux/plat_sepolicy.cil
need_file etc/selinux/plat_file_contexts
OE=u:object_r:herald_exec:s0

# 1. 目录和 broker。plugins/ 是 broker 插件目录,别的补丁的 broker 插件装这里;
#    bin/resetprop 是基础工具(root 改系统属性),attestation-fix、spoof/global-pif、tango 都用它
put_dir etc/herald_payload         0755 0:0 "$OE"
put_dir etc/herald_payload/bin     0755 0:0 "$OE"
put "$HERALD_PAYLOAD/bin/resetprop" etc/herald_payload/bin/resetprop 0755 0:0 "$OE"
put "$MOD/files/herald-start.sh"   etc/herald_payload/herald-start.sh 0755 0:0 "$OE"
put_dir etc/herald_payload/plugins 0755 0:0 "$OE"

# 2. init:boot_completed 后在 herald 域起 broker(seclabel 在 init.herald.rc 里定)
put "$MOD/files/init.herald.rc" etc/init/init.herald.rc 0644 0:0 u:object_r:system_file:s0

# 3. 命令行前端 heraldctl(无特权,普通 shell 能跑)+ heraldctl 插件目录
put "$MOD/files/heraldctl" bin/heraldctl 0755 0:2000 u:object_r:system_file:s0
put_dir etc/heraldctl.d 0755 0:0 u:object_r:system_file:s0

# 4. SELinux:payload 只读目录的 file_contexts + herald 域策略
fc_append "herald_payload 只读目录" <<'FC'
/system/etc/herald_payload(/.*)?    u:object_r:herald_exec:s0
FC
cil_append "herald-core: herald 域" "$MOD/sepolicy.cil"

log "完成"
