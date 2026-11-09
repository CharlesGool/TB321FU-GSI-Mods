# battery/app:电池管理 App(com.lenovo.tb321fu.battery,入口在设置 → 电池,没有桌面图标)+ 它在 herald-apps 里的命令白名单。
# App 只经 herald-apps 通道和 battery 插件说话,所以没打 herald-apps 的底包线就不装 App(其余电池功能照常)。
if ! mod_ran required/general/herald-apps; then
    log "(没打 required/general/herald-apps,不装电池管理 App)"
    return 0
fi
put_dir system_ext/app/TB321FU-Battery 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/TB321FU-Battery.apk" system_ext/app/TB321FU-Battery/TB321FU-Battery.apk 0644 0:0 u:object_r:system_file:s0
put "$MOD/files/com.lenovo.tb321fu.battery.allow" etc/herald_payload/apps/com.lenovo.tb321fu.battery.allow 0644 0:0 u:object_r:herald_exec:s0
