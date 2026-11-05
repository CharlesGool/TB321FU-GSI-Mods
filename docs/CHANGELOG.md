# CHANGELOG — 变更记录

[English](en/CHANGELOG.md) · [Español](es/CHANGELOG.md) · 简体中文

## BP1A user-v1.4(V1)— 2026-11-05

官方 BP1A.250505.005 底包线(`devices/tb321fu-a15-bp1a`)首个正式版,补丁集对齐 ap3a 的 user-v1.4,出完整 9008 刷机包。

### 新增
- `devices/tb321fu-a15-bp1a`:补齐 v1.4 补丁集——接入 `adaptive-refresh-fix`、`free-rotation`、`smooth-display`、`macro-camera-fix`、`pixel-camera`、`tango`(通用补丁,不改位置);新建 `profiles/user-v1.4.txt`;改用 ap3a 的 `IMAGE_PREFIX` 命名。
- `required/tangorpro/tangorpro_bp1a.250505.005/faceunlock`:人脸解锁 BP1A 适配版(Sense 框架类按 BP1A `services.jar` 的构造器签名重编,`apply_hooks` 的 AuthService 锚按重构后的 `registerFaceSensors` 重定位;离线 javac/check_dex/smali-equiv 全过)。

### 修复
- `toolkit/apex/apextool.py`:apksigner 加 `--alignment-preserved true`,保住 `apex_payload.img` 的 4096 页对齐(默认会被重排成 4 字节,导致 capex 重打包后 payload 偏移不对齐)。两条底包线通用。
- `devices/tb321fu-a15-bp1a/device.conf`:`SIGNER` 回退到 `停更/GSI-Signer`(与 ap3a 一致);`BP1A_PROJ` 路径修正;底包改到 `inputs/base-extracted/`(工程目录对齐 ap3a)。

### 验证
- 离线构建 + AVB 链全通过(system 签名、vbmeta_system 重做 flags=0、主 vbmeta 只改 vendor_boot flags=0、9008 逐分区 hashtree/hash 核对)。真机验证待上平板。

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
