# LOG — 维护日志

[English](en/LOG.md) · [Español](es/LOG.md) · 简体中文

## 记录

版本变更见 [CHANGELOG.md](CHANGELOG.md),历史需求与旧交接见 [HISTORY.md](HISTORY.md)。

## 缺陷

暂无。

## 限制

- 人脸解锁、人脸教育页动画依赖专有件(旷视 Megvii SDK、Pixel 原厂素材),不随仓库分发,需自备。
- 换安卓大版本时,改 jar/APEX 的 smali 补丁通常要对照新底包重做;能构建但功能对不对须上真机验。

## 决策

| 日期 | 决策 | 状态 | 原因 |
|---|---|---|---|
| 2026-11-03 | 仓库从数据工程目录内独立成平级项目 | 接受 | 便于单独维护与发布;数据目录用 `TB321FU_DATA` 或平级路径定位 |
| 2026-11-04 | 不分发专有件(Megvii SDK、Pixel 人脸素材) | 接受 | 专有材料不可公开再分发;改为自备 + 文档说明 |
| 2026-11-04 | `spoof set` 预测从 fingerprint 现推 release | 接受 | 目录机型 profile 无 release 字段,原逻辑对 panther_beta 等谎报 `WILL_FALLBACK`,与开机脚本行为不符 |
| 2026-11-04 | system_server 注入启动器默认关 + 一次性标志 | 接受 | 注入 system_server 风险高(bootloop);一次性消费标志防持久化、绝不 kill system_server |
| 2026-11-05 | 出 `user-v1.4` 锚点正式版,删 test-v1.3.x | 接受 | 删 SOTER 后立一个锚点;6 个 test 版用 clean-releases 删除,三个旧正式版保留 |
| 2026-11-05 | BP1A 底包线对齐 ap3a user-v1.4,人脸按版本门控补丁重适配 | 接受 | 官方 BP1A 首个正式版;改 jar 的 smali 补丁需按新底包重做,放版本门控文件夹,通用补丁原位引用 |
| 2026-11-05 | apextool 签名加 `--alignment-preserved true` | 接受 | apksigner 默认把 payload 重排成 4 字节对齐,抹掉 4096 页对齐,capex 重打包后过不了校验 |
| 2026-11-05 | `tango` 补丁的唯一来源改为 tb321fu-tango-patch 仓库,本仓库只放同步副本,用 `make sync-tango` 同步,`make unit` 检查一致 | 接受 | 与 herald-core 相同;补丁和移植教程已分别公开发布 |
| 2026-11-05 | `FaceUnlockSettingsOverlay.apk` 不再入库,教育页素材从 ParanoidSense 上游取,本地编译 | 接受 | 该 APK 内含 Pixel 设置的专有素材,与"不分发专有件"的决定矛盾;旧提交不改写 |

## 交接

进行中:BP1A user-v1.4 在分支 `bp1a-v1.4`(未并入 `main`)。完整 9008 包已出并离线 + AVB 全验,存档在
BP1A 工程 `releases/pixelos_tangorpro_bp1a.250505.005_user-v1.4_optional/`。**待真机验证**(裸刷开机、人脸实录实解、
6GHz 热点、Play/Duck);验证通过后可将 `bp1a-v1.4` 并入 `main`。
