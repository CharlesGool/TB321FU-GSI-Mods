# stale-boot-image — 清掉因改 jar 而过期的预编译产物

## 做什么

`framework.jar` / `services.jar` 被前面的模块改过之后,系统里预编译的 boot image 和 system_server 的 services oat 就过期了。本模块把它们删掉,让 ART 开机时走正常的「干净状态」路径(开机编译一次,缓存到 /data,后续开机复用)。不删的话 ART 每次开机退回 memfd 编译,Hunter 等检测会报警。

本模块自己不改任何 jar。

## 原理

### 为什么改了 jar 就必须删

`framework.jar` 在 bootclasspath 上,它的 dex 被预编译进了 boot image:`boot-framework.{art,oat,vdex}`(真正编入 framework.jar 的那块,`boot-framework.oat` 里能看到 `framework.jar!classesN` 的 dex location),以及聚合的主镜像 `boot.{art,oat,vdex}`。`services.jar` 被预编译成 system_server 的 app image `oat/<arch>/services.{odex,vdex,art}`。

改了 jar 的内容后,这些预编译产物里记的 dex 校验和 / boot image 校验和就对不上了。ART 开机遇到「文件存在但对不上」,保守地退回纯内存(memfd)编译,而且**每次开机都复现**。Hunter App 实测报过「boot.oat/boot.vdex 从 memfd 映射、backing file 已删除」。把这些过期产物删掉,让 ART 在「什么都没有」的状态下走 Android 本来就支持的正常路径 —— 比自己重新 dex2oat 风险低(编译参数要和原厂完全对齐,错了可能开不了机)。这就是 V48-PIF 的修法,实机复测全绿、Play Integrity 能过。

### 怎么知道改过什么:靠标记,不靠别的模块在不在

改 jar 的模块在换完 jar 后调用 `mark_modified`:
- `build-consistency-dialog-fix` → `mark_modified framework/framework.jar`
- `faceunlock/services-hooks` → `mark_modified framework/services.jar`

本模块用 `was_modified` 读标记,按下面决定删什么:

| 标记 | 删什么 |
|---|---|
| 都没有 | 什么也不删,日志写「没有过期产物」,正常退出 |
| 只有 services.jar | 只删 `oat/<arch>/services.*`(6 个文件) |
| framework.jar(不管 services.jar 有没有) | 删 boot image + services oat(34 个文件) |

所以其他模块开不开、开哪几个,本模块都不会出错;全关只留本模块就是空操作。

### services 的 oat 为什么也归 framework.jar 的连带

> 纠正旧 README(旧工程 `faceunlock/README.md` 第 110 行附近)里的说法:「services.jar 换掉后 oat 校验和对不上,ART 会拒绝并改用 jar 里的 dex,理论上不用删 oat」。这不对,V66 实际删了 `oat/arm64/services.*`。

两个原因:一是 `services.odex` 是 system_server 开机就加载的,留着它对不上会跟着走 memfd;二是它编译时依赖 boot image,`framework.jar` 一改,boot image 校验和变,`services.odex` 即使 services.jar 没动也照样过期。所以 framework.jar 或 services.jar 任一被改,都要删 services oat。

### 删哪些、不删哪些(规则,不写死文件名)

对每个架构子目录(`arm`、`arm64`,动态发现):

- framework.jar 改过:删 stem 为 `boot` 和 `boot-framework` 的 `.art/.oat/.vdex`(各带 `.fsv_meta`),加上顶层共享的 `boot.vdex` / `boot-framework.vdex`(arm/arm64 里的同名 `.vdex` 是指向它的符号链接)。
- 任一改过:删 `oat/<arch>/services.{art,odex,vdex}`(各带 `.fsv_meta`)。

**不删** `boot-ext`、`boot-okhttp`、`boot-core-libart`、`boot-framework-adservices`、`boot-telephony-common` 等 —— 它们编的是没改动的 jar(ext.jar/okhttp 等),校验和仍然过,留着让这部分还能用预编译产物、省开机编译。

动手前(framework.jar 改过时)核对 `boot-framework.oat` 确实编入了 `framework.jar`(二进制里 grep `framework.jar!classes`),确认 stem 命名没变、删的是对的那块;不成立就 `die`。

## 改动清单

- **删**(framework.jar 改过时共 34 个,和 V66 删的逐一对上):`framework/{arm,arm64}/{boot,boot-framework}.{art,oat,vdex}` + 各 `.fsv_meta`、`framework/{boot,boot-framework}.vdex` + `.fsv_meta`、`framework/oat/arm64/services.{art,odex,vdex}` + `.fsv_meta`。
- 只改了 services.jar 时只删后面那 6 个。
- 什么都没改时不删。

## 输入

无。架构目录、文件都从当前底包的 `system/framework` 现找。

## 依赖和顺序

- 不 `require_mod` 任何模块,没有它们也能跑(那就是空操作)。
- **必须排在所有改 framework.jar / services.jar 的模块后面**(`device.conf` 的 `MODS` 里放在 `faceunlock/services-hooks`、`build-consistency-dialog-fix` 之后)。排在前面时它看不到标记、什么都不删,而那两个改 jar 的模块发现它已经跑过会直接报错,提醒你调顺序。以后新增的改 jar 的模块,也要在换完 jar 后 `mark_modified`,并排在本模块前面。

## 适用范围和换底包注意

- 底包 boot image 布局变了(不是 `arm`/`arm64` + `boot`/`boot-framework` 这套命名):核对 `boot-framework.oat` 编入 framework.jar 的那步会 `die`,提示去核对布局 —— 这时要按新底包重新确认删除规则,别硬删。
- 删除用 `remove()`,不存在的文件自动跳过并记数;日志会打出实际删了多少个。

## 踩过的坑(带版本)

- **V47→V48**:换上 isBuildConsistent 补丁的 framework.jar 后 Hunter 报 memfd 告警,变量分离实验排除了和 boot cmdline 的关系,确认是 framework.jar 补丁的连带 —— system 里还烤着对旧 framework.jar 编的 boot image。V48 删这 34 个过期产物修复,锁 BL 复测全绿,Play Integrity 能过。
- **dex2oat 的 `execute_no_trans` AVC**:删产物后抓到过一条 `avc: denied { execute_no_trans } ... dex2oat ... permissive=0`。查过 AOSP 原版 plat_sepolicy.cil 本来就只给 dex2oat 域 `execute`(配 type_transition),还有 neverallow 限制,**很可能是策略设计如此、不是漏配**,贸然加 allow 有违反 neverallow 开不了机的风险。删过期产物后 ART 能走通正常编译路径,这条 AVC 不构成阻塞,按计划先不碰。

## 验证

离线(已在 V66 底包上验证):
- 四个改 jar 的模块全开时,删除后 `system/framework` 的文件集合和 V66 的树**逐一相同**(正好少 34 个,没有多删 / 漏删)。
- 只启用 services-hooks + 本模块 → 只删 services oat 那 6 个;只启用 build-consistency-dialog + 本模块 → 34 个;只留本模块 → 0 个(实测结果见交付报告)。

上机:
```bash
adb shell ls /data/dalvik-cache/arm64/          # 开机后 ART 正常编译缓存落在这里
# Hunter/Momo 等检测无 "boot.oat/boot.vdex from memfd" 告警
```
