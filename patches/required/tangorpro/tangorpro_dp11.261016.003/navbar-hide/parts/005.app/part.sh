# navbar-hide/app:导航栏 App(com.lenovo.tb321fu.navbar,一个"隐藏导航栏"开关)+ herald-apps 白名单
# + Settings 的 RRO(设置 → 系统 → 导航模式 → 三按钮导航 / 手势导航 的齿轮页底部加入口,点开就是这个 App)。
# App 经 herald-apps 通道跑 navbar 命令,没打 herald-apps 的就都不装;RRO 必须和 App 一起装(入口指向的 Activity 不在,点了 Settings 会崩)。
if ! mod_ran required/general/herald-apps; then
    log "(没打 required/general/herald-apps,不装导航栏 App 和设置入口)"
    return 0
fi
put_dir system_ext/app/TB321FU-Navbar 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/TB321FU-Navbar.apk" system_ext/app/TB321FU-Navbar/TB321FU-Navbar.apk 0644 0:0 u:object_r:system_file:s0
put "$MOD/files/com.lenovo.tb321fu.navbar.allow" etc/herald_payload/apps/com.lenovo.tb321fu.navbar.allow 0644 0:0 u:object_r:herald_exec:s0
# Settings RRO 引用的是 DP11 SettingsGoogle 的资源 ID(settings-rro/build.sh 按真 APK 生成),换底包要重编
put "$MOD/files/tb321fu-settings-navbar.apk" product/overlay/tb321fu-settings-navbar.apk 0644 0:0 u:object_r:system_file:s0
