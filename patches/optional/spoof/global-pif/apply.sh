# 全局指纹伪装:post-fs-data(zygote 之前)按 profile 用 resetprop 全局覆写 build 指纹。
# 挂在 herald-core 上(要它的 herald 域、resetprop、seed 和 broker 的 spoof 命令),所以必须排在 herald-core 后面。
require_mod required/general/attestation-fix
put "$MOD/files/herald-global-pif.sh" etc/herald_payload/herald-global-pif.sh 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/init.herald-globalpif.rc" etc/init/init.herald-globalpif.rc 0644 0:0 u:object_r:system_file:s0
