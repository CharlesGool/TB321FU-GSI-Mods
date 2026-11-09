# herald-apps:内置功能 App 的通道插件 + 白名单目录。各功能 App 的模块往 apps/ 放 <包名>.allow。
require_mod required/general/herald-core
put "$MOD/files/herald-apps.sh" etc/herald_payload/plugins/herald-apps.sh 0644 0:0 u:object_r:herald_exec:s0
put_dir etc/herald_payload/apps 0755 0:0 u:object_r:herald_exec:s0
