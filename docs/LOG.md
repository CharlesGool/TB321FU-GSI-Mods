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
| 2026-11-05 | 单一仓库;各底包线的补丁按 `required/tangorpro/<底包ID>/` 文件夹隔离;底包工程目录(非 git)对外只发布成品 9008 刷机包 | 接受 | bp1a / cp3a 两条线并行更新,试合并只有自动生成的 `patches/README.md` 索引冲突;拆成多个仓库会让 46 个共用补丁和 toolkit 各拷一份、共用修复要手动同步(navbar-hide 两份拷贝漂移就是例子) |
| 2026-11-05 | 发布号按底包线各自编号:bp1a 首个正式版 `user-v1.0`,未上机的候选 `test-vX.Y.Z` | 接受 | bp1a / ap3a / cp3a 都用 1.4 会撞号分不清是哪条线 |
| 2026-11-05 | `navbar-hide`:新方案(收起高度 1dp)做通用 V1.1,旧方案(0dp)作为 ap3a 的版本门控特例 V1.0 | 接受 | 官方 BP1A 启动器里收起高度还决定手势收尾判定区,0dp 会让"上滑多任务中途掉头"卡死;Mystic 启动器上旧方案稳定且占位真正为 0 |
| 2026-11-05 | `tango` 补丁的唯一来源改为 tb321fu-tango-patch 仓库,本仓库只放同步副本,用 `make sync-tango` 同步,`make unit` 检查一致 | 接受 | 与 herald-core 相同;补丁和移植教程已分别公开发布 |
| 2026-11-05 | `FaceUnlockSettingsOverlay.apk` 不再入库,教育页素材从 ParanoidSense 上游取,本地编译 | 接受 | 该 APK 内含 Pixel 设置的专有素材,与"不分发专有件"的决定矛盾;旧提交不改写 |

## 交接

- **bp1a**:`user-v1.0` 正式版已出(`VERSION=V3 VERSION_LABEL=user-v1.0 PROFILE=user-v1.4`),真机测过的候选 `test-v1.4.1` 与它逐文件比对只差版本标签;
  存档在 bp1a 工程 `releases/pixelos_tangorpro_bp1a.250505.005_user-v1.0_optional/`,旧发布目录已删。`PROFILE` 文件还叫 `user-v1.4.txt`(未改名)。
- **cp3a(Android 17)**:`test-v1.5` 已构建、离线 AVB 全验,但**真机不开机**——2026-11-05 刷入后 bootloop,多次后掉进高通 9008/EDL
  (增量补丁自检通过、system 与完整包逐字节一致,判断卡在 userspace/init 早期,不是 bootloader / AVB / boot.img)。最可疑的是 A17 system 配
  A14 原厂 vendor(原厂 vendor 声明 `ro.vndk.version=34`,A17 底包不带 VNDK apex)。**属未完成线**;下一步先刷未打补丁的 MysticGSI 原版 A17 二分
  (原版也 bootloop → A17-on-A14-vendor 不兼容,要换方向;能开机 → 是补丁集某项破坏的)。设备在 EDL 时重刷 ap3a / bp1a 完整包即可恢复。
  它的 `navbar-hide` 是自己的版本门控拷贝(内容与通用 V1.1 等价),是否改回引用通用版待定。
- **仓库**:`main` 已合入 bp1a 与 cp3a 两条线(`a1c6e6b`,另有 `build-rro.sh` 回退修复),**未推送**:`origin/main` 仍在 `5d0ff8d`。
- **推 GitHub 之前必须做**:① 清历史——bp1a 早期提交里带进过 30MB 的专有 `FaceUnlock.apk` 和 Pixel 素材(`.gitignore` 已改成 `patches/**/faceunlock/…`,
  但旧提交里还有),新仓库可用干净历史起步;② 正式包 7z 有 4.15GB,GitHub Release 单文件上限 2GB,要分卷或放别处。
- 英文 / 西班牙文文档(`docs/en`、`docs/es`)里 bp1a / cp3a 的新条目还没补。
