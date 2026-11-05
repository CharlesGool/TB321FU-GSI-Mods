# 补丁总表

> 由 `toolkit/gen-index.sh` 从各补丁的 `patch.conf` 生成,不要手改。每个补丁的原理看它自己的 README。

补丁按用途放在四个文件夹里,**补丁名就是 `patches/` 下的路径**(选补丁时可以写末尾几段的短名,如 `battery`、`slim`):

- `required/general/` **必须打 · 通用修复**:这个项目是为 TB321FU 做的,所以不管用哪个 GSI 都要打的修复都在这里(按类分文件夹:`hardware-fix/` 硬件功能修复、`bug-fix/` 漏洞修复、`slim/` 精简、`boot-kernel/` boot 和内核、`herald-core`)。
- `required/<底包前缀>/` **必须打 · 特定底包限定**:只有某类 GSI 才需要的修复。文件夹名是底包 ID 的前缀,构建时只有底包 ID 命中才跑(`required/tangorpro/` = 所有 Pixel Tablet 的 GSI:屏幕方向、热点入口;里面再套 `tangorpro_ap3a.241005.015/` = 只有这一版)。底包 ID 取自底包指纹,日志第一行会打印。
- `optional/` **可选**:给用户用的功能,按需选;高级或非原生的默认不打。
- `debug/` **调试**:开发排错、调研、诊断用的补丁(抓日志、探针、root 只读命令…),正常使用不需要,默认都不打;要用时 `WITH=debug` 一次选上。

每个表内按执行顺序(device.conf 的 `MODS`)排,"默认"一栏按 `devices/tb321fu-a15/device.conf`:"打"= 默认打,"不打"= 默认不打,"自动"= 本身不在默认里、但被别的补丁自动带上。大类文件夹(`slim/`、`brightness/`…)本身不是补丁,只用来一次选一批。合并补丁(`battery`、`tango`…)内部的部分(`parts/001.xxx`…,按编号顺序跑)在"包含"一栏,不能单独选。
"要先有"是 `REQUIRES`(选了会自动带上);"登记到"是 `CONTRIBUTES`(会自动带上负责它的 assemble 补丁)。

## 必须打 · 通用修复

| 编号 | 中文名 | 补丁 | 改哪里 | 默认 | 做什么 | 包含 | 要先有 | 登记到 / 负责 | 运行时开关 | 可能的问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 机型还原 | [bug-fix/identity](required/general/bug-fix/identity/) | system | 打 | 机型身份:ro.product.* 改成 TB321FU、指纹和 build 描述符从原厂固件现取、ro.build.display.id 写版本号 | 3 个部分:001.product-fields、002.build-fingerprint、003.version-label |  |  |  | 全局改机型属性和指纹(伪装成 TB321FU),底下仍是 Pixel Tablet 的 GSI;检测软件如果拿属性和实际的分区/挂载方式对照,可能看出不一致,没有专门验证 |
| 2 | 关闭调试 | [bug-fix/debug-off](required/general/bug-fix/debug-off/) | system | 打 | 关调试 |  |  |  |  |  |
| 3 | 精简旧版 VNDK | [slim/old-vndk](required/general/slim/old-vndk/) | system | 打 | 只留 vendor 要用的那个 VNDK apex(读原厂 vendor 的 ro.vndk.version),删其余版本,约 246M |  |  |  |  |  |
| 4 | 隐藏 GSI 痕迹 | [bug-fix/gsi-hide](required/general/bug-fix/gsi-hide/) | system | 打 | 去掉 GSI / 虚拟机痕迹:partition.*.verified 改 1、去掉虚拟机属性标签 | 2 个部分:001.partition-verified、002.qemu-prop-label |  |  |  | 只改属性和 SELinux 标签,不删文件、不动挂载;检测软件从别的途径(挂载、文件、行为)仍可能认出 GSI |
| 5 | 去开机内部问题弹窗 | [bug-fix/build-consistency-dialog-fix](required/general/bug-fix/build-consistency-dialog-fix/) | system | 打 | 去掉开机「设备内部出现了问题」弹窗 |  |  |  |  | 直接让 isBuildConsistent() 返回一致,GSI 和 vendor 真有不兼容时系统也不再弹提示 |
| 6 | herald核心 | [herald-core](required/general/herald-core/) | system | 打 | 免 root 的控制后端:herald 域里的 broker + heraldctl + 插件接口;只提供命令通道、配对和接入方式,具体能力由别的补丁接入 |  |  |  | heraldctl selftest\|pair\|diag |  |
| 7 | 密钥认证 | [attestation-fix](required/general/attestation-fix/) | system | 打 | keymint + inject:用自带 keybox 签出 deviceLocked / verifiedBootState=green 的 keystore2 证书链,附指纹伪装、keybox、本机 RKP、安全补丁同步命令;默认 profile 用本机真实身份(不再是烤进去的 Pixel 7) |  | required/general/herald-core |  | heraldctl spoof\|keybox\|rkp |  |
| 8 | 自动亮度修复 | [hardware-fix/auto-brightness-fix](required/general/hardware-fix/auto-brightness-fix/) | system | 打 | 自动亮度修复:GSI 的自动亮度是坏的。设置里加回自适应亮度开关,换上联想原厂的自动亮度曲线和反应速度,手动最低档也还原原厂(四个静态 RRO + 面板亮度配置) | 5 个部分:001.auto-brightness、002.min-brightness、003.brightness-curve、004.brightness-debounce、005.display-config |  |  |  |  |
| 9 | 自适应刷新率修复 | [hardware-fix/adaptive-refresh-fix](required/general/hardware-fix/adaptive-refresh-fix/) | system | 打 | 自适应刷新率修复:补回原厂 SurfaceFlinger 的空闲/触摸定时器和内容检测(静止降档、触摸升档、视频按帧率),只加属性 |  |  |  |  |  |
| 10 | 蓝牙音频修复 | [hardware-fix/bluetooth-fix](required/general/hardware-fix/bluetooth-fix/) | system | 打 | 蓝牙音频修复:关 A2DP 硬件 offload 和 LE Audio,改走 vendor 软件编码;音频策略和 audio.primary 去掉对应检查(开机 bind 到 vendor),修耳机没声音和通话听不到 | 3 个部分:001.profile-props、002.a2dp-offload-policy、003.sco-call-fix |  |  |  |  |
| 11 | 微距相机修复 | [hardware-fix/macro-camera-fix](required/general/hardware-fix/macro-camera-fix/) | system | 打 | 微距相机修复:把原厂 system 里的 ro.vendor.qti.va_aosp.support=1 补回 GSI,相机 HAL 才按原厂配置报出 2 号微距相机 |  |  |  |  |  |
| 12 | Pixel 相机 | [camera/pixel-camera](required/general/camera/pixel-camera/) | system | 打 | 内置 Google 相机 4.4(Pixel 相机通用版,算法很少、体积小):装成 system/app,原生库放在 APK 旁边 |  |  |  |  | 是 2017 年前后的老版本(SDK 25、target 26),没有新机型的算法优化;APK 自带的是原作者的签名,不是平台签名,权限靠用户在系统里授予;没有在每台设备上验证过所有镜头 |
| 13 | 32 位应用支持 | [tango](required/general/tango/) | system | 打 | 32 位 APK 支持(Tango 二进制翻译):翻译器 + sepolicy + 内核模块 + 32 位 vendor 库 + 32 位 zygote 和开机保险(授权文件不进仓库) | 5 个部分:001.core、002.sepolicy、003.kernel-module、004.vendor-lib32、005.zygote32 | required/general/herald-core |  | heraldctl tango status\|retry\|off\|logs\|zygote32 start\|stop;tango.enabled 属性 |  |
| 14 | 清过期预编译 | [boot-kernel/stale-boot-image](required/general/boot-kernel/stale-boot-image/) | system | 自动 | 清掉因改 jar 而过期的预编译产物 |  |  |  |  | 删掉 framework 的预编译 boot image 和 services oat,开机时由系统重新生成;抓到过一条 dex2oat 的 execute_no_trans AVC,判断是策略本来如此,没有处理 |
| 15 | 内核编译者字符串 | [boot-kernel/kernel-builder-string](required/general/boot-kernel/kernel-builder-string/) | boot | 打 | 内核编译者字符串 |  |  | → boot |  |  |
| 16 | boot 打包重签 | [boot-kernel/boot-assemble](required/general/boot-kernel/boot-assemble/) | boot | 打 | 汇总改动、重签 boot |  |  | 负责 boot |  |  |
| 17 | 联想相机 | [camera/zuicamera](required/general/camera/zuicamera/) | system | 不打 | 联想原厂相机(ZuiCamera)和它在 GSI 上要的修补:辅助镜头清单、相机编号核对、真实机型、屏蔽不支持的功能(含设置页的水印和 OCR 选项) | 5 个部分:001.app、002.aux-camera-list、003.camera-id-check、004.real-device-id、005.hide-unsupported |  |  |  | 联想相机要读真实机型:改全局机型(全局伪装等)会让它无法使用,real-device-id 只能在补丁自己的伪装方式下让它读到真实机型,别的改机型方式不保证;水印等 ZUI 专属处理需要相机 HAL 认出联想相机,这里没有做,所以水印不生效 |

## 必须打 · 特定底包限定(tangorpro)

| 编号 | 中文名 | 补丁 | 改哪里 | 默认 | 做什么 | 包含 | 要先有 | 登记到 / 负责 | 运行时开关 | 可能的问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 精简 Pixel 专属应用和数据 | [tangorpro_ap3a.241005.015/slim/pixel-leftovers](required/tangorpro/tangorpro_ap3a.241005.015/slim/pixel-leftovers/) | system | 打 | 删 TB321FU 用不上的 Pixel 专属东西:Play 自动安装配置、"正在播放"歌曲库、Pixel 相机、儿童模式 |  |  |  |  |  |
| 2 | 精简 Pixel 硬件组件 | [tangorpro_ap3a.241005.015/slim/pixel-hardware](required/tangorpro/tangorpro_ap3a.241005.015/slim/pixel-hardware/) | system | 打 | 删本机没有对应硬件的 Pixel 组件:底座、投屏、零售演示、Tensor 服务、侧边指纹、UWB、强光/UV、基带、NFC 应用(只有 Pixel Tablet 的 GSI 才带) |  |  |  |  |  |
| 3 | 精简 Google 应用(分级) | [tangorpro_ap3a.241005.015/slim/google-slim](required/tangorpro/tangorpro_ap3a.241005.015/slim/google-slim/) | system | 打 | 按 GOOGLE_SLIM 分级删 Google 应用,默认 1:冷门应用(YouTube 全家、Meet、Home、Wellbeing 等);2:再加日常应用(时钟、天气、相册、Gmail、地图等)、Google 助理、GoogleTTS 语音数据、离线语音模型;3:再加无障碍(TalkBack、读屏等);0:不精简。依赖被精简应用的下拉栏磁贴(设备控制等)一并从默认列表去掉 |  |  |  |  | 第 3 级会删 TalkBack 等无障碍应用,需要读屏的用户不要选;第 2 级起删离线语音模型,Live Caption / 离线语音输入可能用不了;覆盖 SystemUI 默认磁贴列表,以后底包换了要更新 tiles.default / tiles.stock |
| 4 | 设备连接服务域修复 | [tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix](required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix/) | system | 打 | 只针对 Pixel Tablet 的 AP3A.241005.015 这一版 GSI:删 seapp_contexts 里指向 dcservice_app 的两行规则(这个域只在 Pixel 的 vendor sepolicy 里有,留着会让设备连接服务每 10 秒崩一次) |  |  |  |  |  |
| 5 | 精简 GSI 残留 | [tangorpro_ap3a.241005.015/slim/gsi-traces](required/tangorpro/tangorpro_ap3a.241005.015/slim/gsi-traces/) | system | 打 | 删 GSI 工具留下的东西:Mystic 的 vendor overlay 和开机 root logcat、phh 的按键布局/远程 adb 隧道/属性处理脚本 | 5 个部分:001.mystic-vendor-overlays、002.mystic-boot-logcat、003.phh-keylayouts、004.phh-remotectl、005.phh-prop-handlers |  |  |  | 其中 phh 的三个部分没有在真机上单独试过,理论上无副作用;刷后要查开机、热点、蓝牙、亮度 |
| 6 | SELinux 修复 | [tangorpro_ap3a.241005.015/bug-fix/selinux/fix](required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/fix/) | system+boot | 打 | SELinux 开机即 Enforcing:system 里删 Mystic 的 permissiver、early-init 就 setenforce 1;boot 的内核命令行加 enforcing=1 selinux=1,内核从第一刻起就是 Enforcing | 2 个部分:001.enforce-at-init、002.kernel-enforcing |  | → boot |  |  |
| 7 | 去 phh 可写挂载 | [tangorpro_ap3a.241005.015/bug-fix/rw-system-tmpfs](required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/rw-system-tmpfs/) | system | 打 | 去掉 phh 脚本的可写 tmpfs 挂载 |  |  |  |  |  |
| 8 | 屏幕方向修复 | [rotation-fix](required/tangorpro/rotation-fix/) | system | 打 | 屏幕方向修复:只能横屏的应用画面不再倒过来;去掉 Pixel Tablet 底座的方向设置(两个静态 RRO) | 2 个部分:001.rotation-reverse-fix、002.dock-rotation-fix |  |  |  |  |
| 9 | 隐藏导航栏(ap3a 旧方案) | [tangorpro_ap3a.241005.015/navbar-hide](required/tangorpro/tangorpro_ap3a.241005.015/navbar-hide/) | system | 打 | 隐藏导航栏(ap3a 旧方案:启动器收起高度 0dp,Mystic 启动器上稳定;其它底包用通用版新方案):三个非静态 overlay(手机模式导航栏、手势提示线、平板任务栏)+ heraldctl 开关和导航模式守护 | 4 个部分:001.overlay-framework、002.overlay-systemui、003.overlay-launcher、004.control | required/general/herald-core |  | heraldctl navbar hide\|show\|status |  |
| 10 | 热点界面修复 | [hotspot-ui-fix](required/tangorpro/hotspot-ui-fix/) | system | 打 | Pixel Tablet 的 GSI 把 WLAN 热点的界面入口关了:设置里的入口和快捷设置磁贴都补回来 | 2 个部分:001.settings-entry、002.qs-tile |  |  |  |  |
| 11 | 6GHz 修复 | [tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix](required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/6ghz-fix/) | system | 打 | 6GHz 热点修复:Wi-Fi 国家码(默认 DE,驱动才允许 6GHz 当 AP)+ 设置里选 6GHz 时把热点固定在 6GHz 频段(信道和带宽不固定) | 2 个部分:001.country-code、002.band-fix |  | → wifi-service-jar | Settings 键 herald_wifi_country;可选 herald_6g_channel / herald_6g_bw / herald_6g_be | Wi-Fi 国家码默认固定为 DE 才能开 6GHz 热点,代价是 5GHz 没有 149–169 信道;6GHz 热点的信道交给驱动自动选(没有固定信道),只有在这台设备上实测过设置里选 6GHz 能开出来才算数;平板同时连着 5GHz Wi-Fi 时 6GHz 热点会被压回 5GHz |
| 12 | Wi-Fi 打包 | [tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble](required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/wifi-apex-assemble/) | system | 打 | Wi-Fi APEX 打包:把前面各个 Wi-Fi 补丁登记的 smali 补丁一次性应用到 service-wifi.jar,回编、重签 APEX 并换进树里;没有任何登记时跳过 |  |  | 负责 wifi-service-jar |  |  |
| 13 | 人脸解锁 | [tangorpro_ap3a.241005.015/faceunlock](required/tangorpro/tangorpro_ap3a.241005.015/faceunlock/) | system | 打 | 人脸解锁:services.jar 的生物识别放行钩子 + FaceUnlock App 和权限 + 设置里的人脸入口 | 3 个部分:001.services-hooks、002.app、003.settings-entry |  |  |  | 人脸是 2D 的(PixelOS ParanoidSense,Megvii SDK),只算 WEAK / Class 2 生物识别,没有深度或红外,安全性比指纹低,用照片或视频可能骗过;services.jar 里还加了生物识别放行钩子,不要用来保护支付、银行这类应用 |
| 14 | 设备连接服务域修复 | [tangorpro_bp1a.250505.005/bug-fix/dcservice-seapp-fix](required/tangorpro/tangorpro_bp1a.250505.005/bug-fix/dcservice-seapp-fix/) | system | 不在目录 | 只针对 Pixel Tablet 的 BP1A.250505.005 这一版 GSI:删 seapp_contexts 里指向 dcservice_app 的两行规则(这个域只在 Pixel 的 vendor sepolicy 里有,留着会让设备连接服务每 10 秒崩一次) |  |  |  |  |  |
| 15 | 去 phh 可写挂载 | [tangorpro_bp1a.250505.005/bug-fix/rw-system-tmpfs](required/tangorpro/tangorpro_bp1a.250505.005/bug-fix/rw-system-tmpfs/) | system | 不在目录 | 去掉 phh 脚本的可写 tmpfs 挂载 |  |  |  |  |  |
| 16 | SELinux 修复 | [tangorpro_bp1a.250505.005/bug-fix/selinux/fix](required/tangorpro/tangorpro_bp1a.250505.005/bug-fix/selinux/fix/) | system+boot | 不在目录 | SELinux 开机即 Enforcing:system 里删 Mystic 的 permissiver、early-init 就 setenforce 1;boot 的内核命令行加 enforcing=1 selinux=1,内核从第一刻起就是 Enforcing | 2 个部分:001.enforce-at-init、002.kernel-enforcing |  | → boot |  |  |
| 17 | 人脸解锁(BP1A 适配) | [tangorpro_bp1a.250505.005/faceunlock](required/tangorpro/tangorpro_bp1a.250505.005/faceunlock/) | system | 不在目录 | 人脸解锁(BP1A 专属版):services.jar 的生物识别放行钩子 + FaceUnlock App 和权限 + 设置里的人脸入口。Sense 框架类按 BP1A 官方 services.jar 的构造器签名重编,apply_hooks 的注入点按 BP1A smali 重新定位 | 3 个部分:001.services-hooks、002.app、003.settings-entry |  |  |  | 人脸是 2D 的(PixelOS ParanoidSense,Megvii SDK),只算 WEAK / Class 2 生物识别,没有深度或红外,安全性比指纹低,用照片或视频可能骗过;services.jar 里还加了生物识别放行钩子,不要用来保护支付、银行这类应用 |
| 18 | 6GHz 修复 | [tangorpro_bp1a.250505.005/hardware-fix/6ghz-fix](required/tangorpro/tangorpro_bp1a.250505.005/hardware-fix/6ghz-fix/) | system | 不在目录 | 6GHz 热点修复:Wi-Fi 国家码(默认 DE,驱动才允许 6GHz 当 AP)+ 设置里选 6GHz 时把热点固定在 6GHz 频段(信道和带宽不固定) | 2 个部分:001.country-code、002.band-fix |  | → wifi-service-jar | Settings 键 herald_wifi_country;可选 herald_6g_channel / herald_6g_bw / herald_6g_be | Wi-Fi 国家码默认固定为 DE 才能开 6GHz 热点,代价是 5GHz 没有 149–169 信道;6GHz 热点的信道交给驱动自动选(没有固定信道),只有在这台设备上实测过设置里选 6GHz 能开出来才算数;平板同时连着 5GHz Wi-Fi 时 6GHz 热点会被压回 5GHz |
| 19 | Wi-Fi 打包 | [tangorpro_bp1a.250505.005/hardware-fix/wifi-apex-assemble](required/tangorpro/tangorpro_bp1a.250505.005/hardware-fix/wifi-apex-assemble/) | system | 不在目录 | Wi-Fi APEX 打包:把前面各个 Wi-Fi 补丁登记的 smali 补丁一次性应用到 service-wifi.jar,回编、重签 APEX 并换进树里;没有任何登记时跳过 |  |  | 负责 wifi-service-jar |  |  |
| 20 | 精简 GSI 残留 | [tangorpro_bp1a.250505.005/slim/gsi-traces](required/tangorpro/tangorpro_bp1a.250505.005/slim/gsi-traces/) | system | 不在目录 | 删 GSI 工具留下的东西:Mystic 的 vendor overlay 和开机 root logcat、phh 的按键布局/远程 adb 隧道/属性处理脚本 | 2 个部分:001.mystic-vendor-overlays、002.nested-system-shim |  |  |  | 其中 phh 的三个部分没有在真机上单独试过,理论上无副作用;刷后要查开机、热点、蓝牙、亮度 |
| 21 | 精简 Pixel 硬件组件 | [tangorpro_bp1a.250505.005/slim/pixel-hardware](required/tangorpro/tangorpro_bp1a.250505.005/slim/pixel-hardware/) | system | 不在目录 | 删本机没有对应硬件的 Pixel 组件:底座、投屏、零售演示、Tensor 服务、侧边指纹、UWB、强光/UV、基带、NFC 应用(只有 Pixel Tablet 的 GSI 才带) |  |  |  |  |  |
| 22 | 精简 Pixel 专属应用和数据 | [tangorpro_bp1a.250505.005/slim/pixel-leftovers](required/tangorpro/tangorpro_bp1a.250505.005/slim/pixel-leftovers/) | system | 不在目录 | 删 TB321FU 用不上的 Pixel 专属东西:Play 自动安装配置、"正在播放"歌曲库、Pixel 相机、儿童模式 |  |  |  |  |  |

## 可选

| 编号 | 中文名 | 补丁 | 改哪里 | 默认 | 做什么 | 包含 | 要先有 | 登记到 / 负责 | 运行时开关 | 可能的问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 刷新率控制 | [refresh-control](optional/refresh-control/) | system | 打 | heraldctl refresh 锁定/限定刷新率(30~165 Hz):写 min/peak_refresh_rate;要 herald-core 在前 |  | required/general/herald-core |  | heraldctl refresh set\|range\|auto |  |
| 2 | 自由旋转 | [free-rotation](optional/free-rotation/) | system | 打 | 允许四个方向都能自动旋转,包括竖屏倒过来(180°);不受"显示大小"影响(显示大小调大后系统会把本机当手机,默认不允许竖屏倒过来) |  |  |  |  |  |
| 3 | 流畅显示档位 | [smooth-display](optional/smooth-display/) | system | 打 | 设置里"流畅显示"开 = 不设上限(面板最高档 165Hz),关 = 120Hz(原来是 60Hz):services.jar 的 DisplayModeDirector 把"peak=60 且 min 没设"当成 120 |  |  |  |  |  |
| 4 | 电池管理 | [battery](optional/battery/) | system | 打 | 电池:寿命查看、长期插电保护、充电上限、旁路充电(heraldctl battery …) | 5 个部分:001.node-access、002.health-report、003.charge-protection、004.charge-limit、005.bypass-charging | required/general/herald-core |  | heraldctl battery info\|protect\|limit\|bypass |  |
| 5 | 解锁 6GHz 热点 | [hotspot-6ghz-unlock](optional/hotspot-6ghz-unlock/) | system | 打 | 解锁 6GHz 热点:能力位、信道列表、设置页信道列表三道门都放开,设置里能选 6GHz 并真的开起来(6GHz 频段修复和国家码在必选的 6ghz-fix) |  |  | → wifi-service-jar |  |  |
| 6 | 热点控制 | [hotspot-control](optional/hotspot-control/) | system | 打 | 热点控制:热点名称/密码/加密/频段等自定义(herald_ap_*)+ heraldctl wifi\|hotspot 命令;6GHz 的信道/带宽/802.11be(herald_6g_*)也从这里的命令设置 | 2 个部分:001.hotspot-custom、002.control |  | → wifi-service-jar | Settings 键 herald_ap_*;heraldctl wifi\|hotspot |  |
| 7 | 全局指纹伪装 | [spoof/global-pif](optional/spoof/global-pif/) | system | 不打 | 全局指纹伪装 |  | required/general/attestation-fix |  | heraldctl spoof set\|off |  |
| 8 | 按应用伪装 | [spoof/app-spoof](optional/spoof/app-spoof/) | system | 不打 | 按 App 伪装 Build.* |  | required/general/attestation-fix |  |  |  |
| 9 | HBM 不限时 | [brightness/hbm-unlimited](optional/brightness/hbm-unlimited/) | system | 不打 | 去掉 HBM(782 尼特)的时间限制:手动拉满可以一直保持面板峰值。不打则 782 尼特最多持续约 5 分钟(30 分钟窗口),之后压回 741 尼特。不要求强光这一条由自动亮度修复负责 |  |  |  |  |  |
| 10 | 按应用/电量自动换刷新率 | [refresh-auto-switch](optional/refresh-auto-switch/) | system | 不打 | 按前台应用、低电量自动换刷新率(heraldctl refresh adaptive\|app\|default\|battery);要刷新率控制在前 |  | required/general/herald-core optional/refresh-control |  | heraldctl refresh adaptive\|app\|default\|battery |  |
| 11 | overlay 缓存自愈 | [overlay-idmap-reset](optional/overlay-idmap-reset/) | system | 不打 | 开机删我们 overlay 的旧 idmap(坏 idmap 会让 idmap2d 崩) |  |  |  |  |  |
| 12 | 游戏模式 | [game-mode](optional/game-mode/) | system | 不打 | 游戏模式:游戏名单与前台触发、锁住退出途径(导航/通知栏/快捷设置)、自动勿扰 | 3 个部分:001.foreground-trigger、002.kiosk-lock、003.auto-dnd | required/general/herald-core |  | heraldctl game add\|remove\|list\|on\|off\|release\|flags\|combo\|dndmode |  |
| 13 | 性能调节 | [perf](optional/perf/) | system | 不打 | 性能调节:CPU 各簇频率上下限、GPU 频率上下限、省电/均衡/性能一键切档、CPU/GPU/外壳/电池温度读数(heraldctl perf …) | 5 个部分:001.node-access、002.cpu-freq、003.gpu-freq、004.profiles、005.thermal-readout | required/general/herald-core |  | heraldctl perf cpu\|gpu\|profile\|temps |  |
| 14 | 游戏性能联动 | [perf-game-boost](optional/perf-game-boost/) | system | 不打 | 游戏模式的性能档钩子 |  | optional/game-mode required/general/herald-core optional/perf |  | heraldctl game perfprofile |  |
| 15 | 状态栏网速 | [statusbar-netspeed](optional/statusbar-netspeed/) | system | 不打 | 状态栏网速:framework 里加类把网速插进状态栏(不改 SystemUI 的 APK)+ heraldctl 开关和样式 | 2 个部分:001.display、002.control | required/general/herald-core |  | heraldctl netspeed on\|off\|pos\|mode\|unit |  |
| 16 | 开发者选项隐藏 | [devopts-hide](optional/devopts-hide/) | system | 不打 | 按 App 隐藏开发者选项 / ADB 状态:framework.jar 里加类 + 四处钩子,名单里的 App 读这几项设置得到 0;heraldctl hide devopts 管开关、模式和名单,改完重启生效 | 2 个部分:001.hook、002.control | required/general/herald-core |  | heraldctl hide devopts on\|off\|mode\|add\|remove |  |
| 17 | 自定义字体 | [custom-font](optional/custom-font/) | system | 不打 | 自定义系统字体:SystemFonts 改读 /data/fonts/herald/ 的字体包(不挂载、不占 system)+ heraldctl 装包/选用/撤回 | 2 个部分:001.hook、002.control | required/general/herald-core |  | heraldctl font install\|use\|reset\|list |  |
| 18 | 应用备份还原 | [app-backup](optional/app-backup/) | system | 不打 | App 备份 / 还原 |  | required/general/herald-core |  | heraldctl backup app\|restore\|list\|delete\|job |  |
| 19 | 隐藏导航栏 | [navbar-hide](optional/navbar-hide/) | system | 不在目录 | 隐藏导航栏(V1.1:启动器收起高度 1dp,Taskbar 下不强切导航模式):三个非静态 overlay(手机模式导航栏、手势提示线、平板任务栏)+ heraldctl 开关和导航模式守护 | 4 个部分:001.overlay-framework、002.overlay-systemui、003.overlay-launcher、004.control | required/general/herald-core |  | heraldctl navbar hide\|show\|status |  |
| 20 | 精简无障碍应用 | [slim/accessibility](optional/slim/accessibility/) | system | 不在目录 | 删无障碍应用(读屏、屏幕切换、声音放大器、Scribe 等);需要读屏的用户不要打 |  |  |  |  |  |
| 21 | 精简 Google 应用 | [slim/google-apps](optional/slim/google-apps/) | system | 不在目录 | 删 Google 预装应用、Google 助理和 GoogleTTS 语音数据(能从 Play 装回来;想留着 Google 应用就别打) |  |  |  |  |  |

## 调试

| 编号 | 中文名 | 补丁 | 改哪里 | 默认 | 做什么 | 包含 | 要先有 | 登记到 / 负责 | 运行时开关 | 可能的问题 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | adb 可抓日志 | [shell-logcat](debug/shell-logcat/) | system | 不打 | Enforcing 下 adb 能 logcat |  |  |  |  |  |
| 2 | 开机自动开 ADB | [adb-on-boot](debug/adb-on-boot/) | system | 不打 | 开机自动启用 ADB,并且免授权/免配对(ro.adb.secure=0,连电脑不弹授权框);不管 root(见 herald-rooted-shell);排在 debug-off 后面执行,把它关掉的都加回来。测试用 | 2 个部分:001.on-boot、002.no-auth |  |  |  |  |
| 3 | adb root | [rooted-adbd](debug/rooted-adbd/) | system | 不打 | 让 adb root 能用:ro.debuggable=1,并把 adbd 和 shell 域设成 permissive;不改开机启用 ADB 和授权(那是 adb-on-boot),也不让 adbd 开机就是 root |  |  |  | adb root(按需,不是开机 root) |  |
| 4 | root 只读命令 | [herald-readonly-shell](debug/herald-readonly-shell/) | system | 不打 | 以 root 跑只读查看命令 |  | required/general/herald-core |  | heraldctl rexec on\|off,默认关 |  |
| 5 | root shell | [herald-rooted-shell](debug/herald-rooted-shell/) | system | 不打 | 经 herald broker 以 root 跑任意命令(经 sh -c,支持管道和重定向),默认关、限时打开、只接受命令行;不需要 debug/adb 的免授权和 ro.debuggable |  | required/general/herald-core |  | heraldctl rsh on\|off,默认关 |  |
| 6 | zygote 时序测量(调研) | [herald-zygisk-timing-probe](debug/herald-zygisk-timing-probe/) | system | 不打 | 测量开机时 post-fs-data 到 zygote 启动的时间窗口(调研用,只读,默认不打) |  | required/general/herald-core |  |  |  |
| 7 | zygote 注入点验证(调研) | [herald-zygisk-fork-observer](debug/herald-zygisk-fork-observer/) | system | 不打 | 真机验证 ptrace 住 init、在 zygote64 执行第一条指令前截停它这条链路(调研用,只观察不注入,默认不打) |  | required/general/herald-core |  |  |  |
| 8 | 开机相机日志(诊断) | [diag-boot-camera-log](debug/diag-boot-camera-log/) | system | 不打 | 开机时记下相机驱动的日志(诊断用) |  | required/general/herald-core |  |  |  |

