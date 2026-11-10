# CHANGELOG — 变更记录

[English](en/CHANGELOG.md) · [Español](es/CHANGELOG.md) · 简体中文

## DP11 未发布(test-v2.0 … test-v3.0)— 2026-11-09

user-v1.9 之后的测试版,以下改动都在 DP11 线上机跑过(test-v2.0 起陆续验证),等下一个正式版一起发布。

### 新增
- `required/general/herald-apps` V1.0:内置功能 App 的专用通道。每个功能做成一个装在系统分区的小 App,入口注入设置;不用配对,鉴权 = 包装在系统分区 + uid 一致,每个 App 只能跑 `apps/<包名>.allow` 白名单里的命令;支持附带数据(spoof set / keybox import)。回包 O_EXCL 新建后 `chown -h` + `chcon -h`(App 数据文件带 MLS 类别,不改上下文 App 打不开)。
- 电池管理 App(`battery` 的 `006.app`,设置 → 电池):电池健康、双电芯、实时状态、充电上限、长期插电保护、旁路充电。
- 机型伪装与密钥认证 App(`attestation-fix` V1.3,设置 → 关于平板电脑 → 型号下面):全局机型伪装(从 Pixel 机型目录选)、Keybox 类型 / 证书状态 / 证书链 / 更换、本机 RKP 签发与导入。插件加 `spoof_on <机型>`(apply 后直接用 keymint 写好的规范 profile 走 set)。
- 导航栏 App(DP11 `navbar-hide` V1.2 的 `005.app`):入口在 设置 → 系统 → 导航模式 → 三按钮 / 手势导航的齿轮页底部,用 Settings 的静态 RRO 加进去(导航模式页不支持注入)。
- `required/general/hardware-fix/vibrator-hal` V1.2:系统侧 `IVibratorManager/default`(tb321fu-vibrator),两颗 Awinic 马达都认,支持 primitives / 组合 / 同步振动。
- `required/general/qs-auto-brightness` V1.1:快捷设置"自动亮度"开关,长按进 显示和触控。
- `required/general/hardware-fix/wifi-only` V1.0:按纯 Wi-Fi 平板处理(去 dsds 双卡、telephony 特性、voice/sms/data capable)。
- `required/general/hardware-fix/power-profile` V1.0:power_profile 补 `audio` / `video` 键名,电池用量里音视频耗电不再是 0。
- `required/general/bug-fix/herald-quiet` V1.0:herald 域 dontaudit,dmesg 不再被 herald 的 avc 冲掉。
- `required/general/hardware-fix/torch-levels` V1.1:手电筒亮度滑块真正生效。vendor 相机 HAL 忽略档位(固定两颗各 75 mA)、亮着改档还会关掉第二颗灯;常驻小 App 监听 TorchCallback,经 herald 按档位重写 PMIC 闪光灯节点(1~3 档单颗 50/100/200 mA,4 档两颗各 300 mA)。V1.1 修 test-v2.6 实测的三处:关灯后已在路上的写入把灯重新点亮(请求按序排队 + 关灯发 `torch off`)、单颗电流只有一半(补写 `torch_0=2X`)、改档约 1 秒才生效(防抖 80 ms,herald-apps 轮询 0.2 秒)。V1.2 修 test-v2.7 实测的:经 sysfs 写 0 会摘掉相机 HAL 的 LED trigger,手电筒坏到重启(写 0 后挂回 trigger,每条命令和开机时自愈;关灯只在灯还亮时补写);重启后首次解锁前档位不生效(App `directBootAware`,通道放 DE 存储);改档等待再缩短(开灯立刻发、改档防抖 40 ms)。V1.3 按 test-v2.8 上的原型验证结果改通道:App 只写一份最新状态到 DE 的 `torch_state`(原子 rename),herald 常驻 watcher 用 inotify 读到就执行最新一行(0 次 fork,原型实测 21~51 ms 收敛),不再走 herald-apps 请求通道(一次往返 0.35~0.57 秒、排队后过时的 off 会关掉新开的灯),白名单去掉;灯亮时 App 每 150 ms 读一次档位,兜底丢失的 LEVEL 回调;直接点开跟随 HAL 报的档位(当前 4 档)。V1.4 修 test-v2.9 反馈的"从关闭打开 1 / 2 档先闪一下亮光"(HAL 每次开灯先用自己的 75+75 mA 点亮约 25 ms):关灯后摘掉 torch0 / torch3 的 trigger 并给 `torch_0` 预载 25(12.5+12.5 mA),HAL 开灯只能由暗变亮;相机被打开时 App 发布 `cam`,trigger 全部挂回,相机补光 / 预闪走原厂流程。
- herald 引擎 inject 载荷(herald-core c80b798):注入 keystore2 的载荷不再在 keystore2 里起常驻配置监听线程。该线程随 keystore2 常驻,herald 重启重新注入后旧载荷映射失效、线程下次 libc 调用即段错误并拖垮 keystore2(keystore 随之锁定,分享 WLAN 等需认证操作闪退,要重新解锁才恢复;test-v2.9 问题 #2)。载荷不需要实时重载(重新注入时会重读配置);一次性的注入器进程里保留。
- `required/general/bug-fix/qti-testscripts-fix` V1.0:补原厂 vendor rc 用到的两个 QTI 调试脚本 SELinux 类型(不给权限),开机 init 子进程不再 SIGABRT 两次。
- `toolkit/tests/test-herald-apps.sh`、`test-torch-plugin.sh`;`test-battery-plugins.sh` 加 mksh 和 V1.2 用例。

### 变更
- `herald-apps` V1.2:同时服务 DE 存储(`/data/user_de/0/<包>/files`,解锁前可用);刚处理过请求的 3 秒内每 0.05 秒轮询。
- `herald-quiet` V1.1:另外静默 init 起 herald 域服务时的 noatsecure / rlimitinh / siginh(只 dontaudit,不放行)。
- `battery` V1.2:节点读取改用 shell 内建(不再每个节点 fork cat/tr)、不变的值每次开机只读一次、新增 `battery overview`(一次读完 info + 三个 status)、`battery info` 带整机 `soh` / `cycle_count` / `charge_full_uah` / `charge_full_design_uah`。

### 修复
- 振动(vibrator-hal):haptic_hv 每颗马达只有 1 个 FF 槽位,换效果类型前先 `EVIOCRMFF`(第三方 App 的 one-shot 全部 ENOSPC 不振);≤30 ms 的 one-shot 走 RAM 波形;不空发 stop;init 要能 search herald_payload 目录(test-v2.2 卡开机的原因);马达按 i2c 名找。

## DP11 user-v1.9(V10)— 2026-11-09

DP11 线正式版(标准 `user-v1.9` + 自用 `user-v1.9-cust_bebug`),上一个正式版是 user-v1.5。中间的 test-v1.6、BTtest-v1.7、test-v1.8 是测试版。tag `dp11-user-v1.9`。

### 新增
- `required/general/hardware-fix/dt2w` V1.1:双击唤醒。静态 RRO 把 `config_supportDoubleTapWake` 设为 true(设置 → 显示 → 其他显示控制 → 点按唤醒),herald 插件把 `Secure.double_tap_to_wake` 同步到 Novatek 触摸的 `/proc/gesture_control`;`heraldctl dt2w on|off|status`。V1.0(只有插件,开机 fabricated overlay)在 test-v1.8 上机验证;V1.1 的静态 RRO 是因为 fabricated overlay 撑不过重启而加的,未单独上机。

### 变更
- 蓝牙改用 DP11 专用的 `required/tangorpro/tangorpro_dp11.261016.003/hardware-fix/bluetooth-fix` V2.0:A2DP 和 LE Audio(LC3)走高通 ADSP 硬件卸载,vendor 用原厂音频策略(不再 bind 改过的 `audio_policy_configuration.xml`,`persist.bluetooth.a2dp_offload.disabled=false`);打开 LE Audio profile,耳机详情里出现"LE 音频"。SCO 通话补丁保留。其他底包线仍用 general 的 V1.0。BTtest-v1.7(A2DP AAC 卸载)和 test-v1.8(LE Audio 左右耳)上机验证。

### 修复
- `required/general/hardware-fix/video-freeze-fix` V1.1(唯一来源是独立仓库 [tb321fu-video-freeze-patch](https://github.com/CharlesGool/tb321fu-video-freeze-patch),`make sync-video-freeze` 同步):X 等 app 刷视频时声音继续、画面定格。两个独立原因各改 1 条指令:高通解码器申请输出缓冲超时后放弃重试(补丁版 `libqcodec2_v4l2codec.so` 开机 bind 到 /vendor);A17 `Surface::disconnect` 清零 generation(`libgui.so` 那条改 NOP)。排查过程见 [gsi-codec2-video-freeze-guide](https://github.com/CharlesGool/gsi-codec2-video-freeze-guide)。BTtest-v1.7 上机验证。
- LE Audio 下 VoIP(TG/X 语音)下行约 60 秒延迟:vendor `btaudio_offload_if.so` 把 LE 会话的 `peerDelayUs`(微秒)当毫秒报给 PAL,补丁版先 /1000 再上报,开机 bind 到 /vendor(bluetooth-fix V2.0 的 `003.le-audio-latency`)。test-v1.8 上机验证,TG 语音实时。

## BP1A user-v1.0(V3)— 2026-11-05

官方 BP1A.250505.005 底包线(`devices/tb321fu-a15-bp1a`)首个正式版,补丁集对齐 ap3a 的 user-v1.4,出完整 9008 刷机包。发布号按底包线各自编号(此前的 `user-v1.4` / `test-v1.4.1` 是过渡命名,已被取代并删除)。

### 新增
- `devices/tb321fu-a15-bp1a`:补齐 v1.4 补丁集——接入 `adaptive-refresh-fix`、`free-rotation`、`smooth-display`、`macro-camera-fix`、`pixel-camera`、`tango`(通用补丁,不改位置);新建 `profiles/user-v1.4.txt`;改用 ap3a 的 `IMAGE_PREFIX` 命名。
- `required/tangorpro/tangorpro_bp1a.250505.005/faceunlock`:人脸解锁 BP1A 适配版(Sense 框架类按 BP1A `services.jar` 的构造器签名重编,`apply_hooks` 的 AuthService 锚按重构后的 `registerFaceSensors` 重定位;离线 javac/check_dex/smali-equiv 全过)。

- `optional/navbar-hide` V1.1(通用新方案):启动器收起高度 0dp → 1dp,底部栏是 Taskbar 时只杀启动器、不再强切导航模式,修官方 BP1A 启动器上"上滑多任务中途掉头"导致 App 点不动、侧滑失效。旧方案 V1.0(0dp)作为 `required/tangorpro/tangorpro_ap3a.241005.015/navbar-hide` 版本门控特例留给 ap3a。

### 修复
- `toolkit/apex/apextool.py`:apksigner 加 `--alignment-preserved true`,保住 `apex_payload.img` 的 4096 页对齐(默认会被重排成 4 字节,导致 capex 重打包后 payload 偏移不对齐)。两条底包线通用。
- `devices/tb321fu-a15-bp1a/device.conf`:`SIGNER` 回退到 `停更/GSI-Signer`(与 ap3a 一致);`BP1A_PROJ` 路径修正;底包改到 `inputs/base-extracted/`(工程目录对齐 ap3a)。

- `toolkit/lib/build-rro.sh`:找不到 Debian 的 `android-framework-res` 时回退到 SDK 的 `android.jar`(否则 ap3a 构建在 `google-slim` 生成磁贴 overlay 这步失败)。

### 验证
- 离线构建 + AVB 链全通过(system 签名、vbmeta_system 重做 flags=0、主 vbmeta 只改 vendor_boot flags=0、9008 逐分区 hashtree/hash 核对)。候选包 `test-v1.4.1` 已上真机验证通过;`user-v1.0` 与它逐文件比对,只差版本标签、一行注释路径和 Wi-Fi APEX 重签的外壳。

## user-v1.4(V133)— 2026-11-05

删 SOTER、清理引擎后的锚点正式版,**无功能更新**(补丁集同 user-v1.3)。

### 变更
- 引擎换成 herald-core V1.5(删 SOTER + 去 AGPL),keymint/inject 行为不变,三绿真机已验。

### 修复
- `attestation-fix`:broker `spoof set` 的 `WILL_FALLBACK` 误报——预测改为从 fingerprint 现推 release,和 `herald-global-pif.sh` 一致(目录机型 profile 无独立 release 字段时不再谎报回落)。

### 新增(默认关)
- `attestation-fix`:实验性 `inject --target system_server` 门控启动器(一次性标志 `/data/local/tmp/herald_ss_inject`,读到即消费,绝不 kill system_server)——P2.0 验证用,默认不触发。真机验证注入 system_server 被 SELinux 拒(rc=1,安全无副作用),P2 搁置。

## user-v1.3(V132)— 2026-11-04

### 变更
- herald-core 升到 V1.3(工作目录回归修复),认证引擎换成含安全加固的新构建。
- 补丁集同 user-v1.2。

## user-v1.2(V129)— 2026-11-03

### 修复
- 蓝牙:`vendor-bind` 补 `update_engine` 的 SELinux 权限。

### 变更
- 去掉 test 标签重新构建(`ro.tb321fu.mod_version=user-v1.2`)。
