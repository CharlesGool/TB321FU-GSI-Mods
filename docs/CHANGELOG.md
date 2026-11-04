# CHANGELOG — 变更记录

[English](en/CHANGELOG.md) · [Español](es/CHANGELOG.md) · 简体中文

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
