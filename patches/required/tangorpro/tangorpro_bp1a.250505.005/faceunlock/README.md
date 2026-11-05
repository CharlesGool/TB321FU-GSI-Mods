# faceunlock — 人脸解锁(ParanoidSense + 旷视 Megvii)· BP1A 适配版

> **BP1A 专属版本**(底包 ID 门控:`required/tangorpro/tangorpro_bp1a.250505.005/`)。与通用 `optional/faceunlock`
> 的区别只在 `parts/001.services-hooks` 的 Sense 框架类源码和 `apply_hooks.py` 的 AuthService 注入锚,照
> 官方 BP1A.250505.005 的 `services.jar` 重新适配(通用版是对 AP3A/Mystic 写的,直接编不过)。依据见 BP1A 工程
> `doc/08-V8-BUILD.md` §5b。改动:
> - `HalClientMonitor` 子类(FaceUpdateActiveUser/ResetLockout/SetFeature/GetFeature)super 末尾加 `isMandatoryBiometrics=false`;
> - `FaceRemovalClient` 加 `int reason` 透传给 `RemovalClient`;`FaceInternalCleanupClient.getRemovalClient` 同步加 `reason`;`SenseProvider` 两处 `new FaceRemovalClient` 传 `3`;
> - 删 `FaceAuthenticationClient.handleFailedAttempt`(BP1A 该方法变 `final`,基类版是超集);
> - `BiometricTestSessionImpl` 实现新抽象方法 `getSensorId()`;
> - `apply_hooks.py`:BP1A 把 `registerFaceSensors` 重构、`"AuthService"` tag 提到方法头,注入锚改为"方法头 tag 后 `canUseProvider()` + `if-nez :cond_1`",保留老锚兼容。
>
> 离线验证:javac 干净、`check_dex` 0 问题、3/3 Sense 入口、57/57 `USE_BIOMETRIC_INTERNAL` 放行、`smali-equiv` 回编一致。换底包/真机注意同下。

> 一个补丁(`faceunlock`),内部 3 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`faceunlock`),内部 3 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

## 解决什么问题

把 PixelOS 的 ParanoidSense 人脸方案(基于旷视 Megvii SDK,WEAK / Class 2 生物识别)bake 进 GSI 的 system。装完后设置里有「人脸解锁」入口,能录入、能解锁。包名用 `com.android.faceunlock`(不是上游的 `co.aospa.sense`),避开把 `co.aospa.sense` 当作第三方 ROM 特征的检测。

人脸由三部分撑起来,每一部分是一个模块:

1. **框架侧(`services-hooks`)**:在 system_server 里注册 `SenseProvider` 当人脸 HAL 的替身,放开 `USE_BIOMETRIC_INTERNAL` 校验。
2. **应用本体(`app`)**:`com.android.faceunlock`,跑旷视 SDK、开相机、做识别,加上权限 / 白名单 / feature 声明。
3. **设置入口(`settings-entry`)**:让设置里的人脸录入流程指向 App。

## 模块表

| 部分 | 做什么 | 能不能单独关 | 运行时开关 |
|---|---|---|---|
| [`services-hooks`](parts/001.services-hooks/README.md) | 改 services.jar(57 处放行 + Sense 入口 + 新增 classes4.dex),加 `ro.face.sense_service=true` | 能(`WITHOUT=faceunlock/services-hooks`) | 无 |
| [`app`](parts/002.app/README.md) | `FaceUnlock.apk`(priv-app)+ 4 份权限 / 白名单 / 默认权限 xml | 能 | 无 |
| [`settings-entry`](parts/003.settings-entry/README.md) | 设置里人脸入口的静态 overlay | 能 | 无 |

"运行时开关"指刷机后不用重刷、靠设置或属性就能开关该功能的办法。这一组都没有。`ro.face.sense_service` 是只读属性(`ro.`),改它要重刷。

## 顺序和依赖

- 三个模块**互不依赖**:没有 `require_mod`,构建时谁先谁后都行,任意子集都能跑通,不会互相改对方的文件。
- 唯一的顺序要求来自 framework 组:`services-hooks` 改了 services.jar 并打了 `mark_modified framework/services.jar`,要让 `stale-boot-image` 排在它**后面**,才能清掉过期的 services oat。`MODS` 里现在就是这样排的。不启用 `stale-boot-image` 也不会出错,只是 services.odex 过期没删(system_server 开机走 memfd 编译,Hunter 报警,功能不受影响)。
- `services-hooks` 编译时读 `framework.jar` 当 classpath,所以和 `build-consistency-dialog-fix` 谁先谁后都行。

## 单独启用一个会怎样

| 启用 | 结果 |
|---|---|
| 三个都开 | 完整的人脸解锁 |
| 只开 `services-hooks` | services.jar 补丁和属性都在,`SenseProvider` 注册了,但没有 `com.android.faceunlock` 可绑,设置里也没入口。人脸用不了,没有别的副作用 |
| 只开 `app` | App 和权限 xml 装上了,但 system_server 里没有 `SenseProvider`、没人放行 `USE_BIOMETRIC_INTERNAL`,人脸用不了。App 不会被启动。`android.hardware.biometrics.face` feature 声明了而没注册传感器,设置的表现没有实测 |
| 只开 `settings-entry` | 只是个静态 overlay,没有 App 和框架,入口要么不出现要么点不开 |
| `services-hooks` + `app` | 框架和 App 都就位,系统层面能认证;但设置里的录入流程没指向 App 的 `EnrollActivity`,没法用 App 的界面录脸 |
| `app` + `settings-entry`(没有 hooks) | 入口和 App 都在,但 system_server 里没有 Sense 框架,录入失败 |

要用人脸解锁,三个一起开。真正用设备验证过的只有三个全开的组合;其余组合的结论来自代码(谁读什么、谁调用谁),没有逐个上机试。

## 构建与第三方来源

- 所有预编译 APK 放在各自模块的 `files/`;源码和构建脚本在各自的 `src/`。
- **旷视 Megvii SDK** 来自 PixelOS ParanoidSense 上游固定 commit,不进仓库,重建 App 时用 `app/src/fetch_upstream.sh` 拉。
- `app/src/build.sh` 借用 `services-hooks/src/` 里的 AIDL stub 源码和 `check_dex.py`,所以**重建 App** 时这两个模块目录要都在;只**装**预编译 APK 不依赖。
- 参数在 `devices/<设备>/conf.d/faceunlock.conf`:`FU_D2J`、`FU_R8`(8.5.35)、`FU_JAVA_HOME` 给 services-hooks;`FACEUNLOCK_KEYSTORE` 只在重建 APK 时用。

## 整组独立发布时要带什么

`patches/optional/faceunlock/` 整个 + `toolkit/`(`common.sh`、`jarpatch.py`)+ `conf.d/faceunlock.conf` 里的变量。services-hooks 还依赖 `stale-boot-image` 做善后(可选,不带也能跑)。第三方旷视文件用户自己通过 `fetch_upstream.sh` 拉。

## 版本

三个模块的改动在 V66 底包上验证过:services.jar 的 4 份 dex、两个 APK、4 份 xml 和 V66 逐字节相同,`ro.face.sense_service=true` 在 build.prop 里。各模块 README 的"验证"一节有细节。
