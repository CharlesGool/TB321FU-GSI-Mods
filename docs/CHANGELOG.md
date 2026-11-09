# CHANGELOG — 变更记录

[English](en/CHANGELOG.md) · [Español](es/CHANGELOG.md) · 简体中文

## DP11 test-v1.6(V7)— 2026-11-09

DP11 线候选版,未上真机(所以是 test)。补丁集 = user-v1.5 + 下面一项。

### 修复
- `required/general/hardware-fix/video-freeze-fix` V1.1(新,唯一来源是独立仓库 [tb321fu-video-freeze-patch](https://github.com/CharlesGool/tb321fu-video-freeze-patch),`make sync-video-freeze` 同步):X 等 app 刷视频时声音继续、画面定格(拖进度条恢复)。两个独立原因各改 1 条指令:
  - `001.codec2-alloc-retry`:高通 vendor 解码器申请输出缓冲超时后"距上次输入 >1s 就放弃",输入槽又被它自己占满 → 死锁。改成超时后永远重试;补丁版 `libqcodec2_v4l2codec.so` 用 vendor-bind 开机盖到 /vendor(vendor 分区不动)。A15/A17 都有这个问题。
  - `002.libgui-surface-gen`:A17 `Surface::disconnect` 清零 generation,HIDL Codec2 切 Surface 时缓冲迁移全部失败。`libgui.so` 里那条清零改 NOP;A15/A16 的 libgui 没有这段,自动跳过。
  - 排查全过程和通用方法见 [gsi-codec2-video-freeze-guide](https://github.com/CharlesGool/gsi-codec2-video-freeze-guide)。2026-11-09 刷 `BTtest-v1.7-cust_bebug` 真机验证:X 刷视频不再卡画面。

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
