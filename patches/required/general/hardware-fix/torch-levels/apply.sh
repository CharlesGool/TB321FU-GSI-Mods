# torch-levels:herald 插件(常驻 watcher,inotify 读 App 的状态文件,按档位写 PMIC 闪光灯节点)+ 常驻小 App(监听 TorchCallback,写最新状态)。
# V1.3 起不走 herald-apps 请求通道(太慢、会排队),不再装白名单。
require_mod required/general/herald-core
put "$MOD/files/torch.sh" etc/herald_payload/plugins/torch.sh 0644 0:0 u:object_r:herald_exec:s0
put_dir system_ext/app/TB321FU-Torch 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/TB321FU-Torch.apk" system_ext/app/TB321FU-Torch/TB321FU-Torch.apk 0644 0:0 u:object_r:system_file:s0
