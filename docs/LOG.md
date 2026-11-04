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

## 交接

未发现进行中的工作。当前分支 `main`,与 `origin/main` 同步。
