# faceunlock/services-hooks — services.jar 里的人脸解锁补丁

## 做什么

给 `services.jar` 装上人脸解锁的框架侧:在 system_server 里注册一个 `SenseProvider` 当人脸 HAL 的替身,并放开人脸相关接口的 `USE_BIOMETRIC_INTERNAL` 权限校验。同时在 `build.prop` 里加 `ro.face.sense_service=true`。App、设置入口、权限 xml 不在这里(见 `faceunlock/app`、`faceunlock/settings-entry`)。

## 原理

### 为什么必须改 services.jar

`SenseProvider` 在 system_server 里,靠 `ro.face.sense_service=true` 注册(见 `SenseHooks.getProviders`)。但人脸录入/认证的 AIDL 接口(FaceService / BiometricService / AuthService)要求调用方持有 `USE_BIOMETRIC_INTERNAL`,FingerprintService 里还有一处;而这台机器上 `USE_BIOMETRIC_INTERNAL` 和 `MANAGE_BIOMETRIC` 的 protection 都是 `signature`(不是 `signature|privileged`),privapp 白名单对 signature 无效 —— 自签名的 FaceUnlock.apk 两个权限都拿不到。所以必须 patch services.jar,让这些校验走我们的 `SenseHooks` 放行。

### 改了什么

`src/apply_hooks.py` 在 apktool 反编译出的 smali 上打补丁(幂等,打完会扫全树确认残留 `USE_BIOMETRIC_INTERNAL` 调用点为 0):

1. **3 处 Sense 入口**:`AuthService.registerFaceSensors`(没人脸 HAL 也继续注册)、`FaceService$FaceServiceWrapper.getProviders`(先走 `SenseHooks.getProviders`,返回非空就用 SenseProvider)、`registerAuthenticators` 的 `canUseProvider` 兜底。
2. **57 处 `USE_BIOMETRIC_INTERNAL` 放行**:52 处是 AIDL `@EnforcePermission` 展开的 `foo_enforcePermission()`(FaceServiceWrapper 32 + BiometricServiceWrapper 17 + AuthServiceImpl 3),换成 `SenseHooks.enforceInternal()`;另 5 处是直接的 `Utils.checkPermission` / `Context.enforceCallingOrSelfPermission` / `checkCallingOrSelfPermission`;外加 `Utils.hasInternalPermission` 方法体。
3. **priv-app 身份放行(`SenseHooks`)**:放行条件是「调用方是 system/root/本进程,或真持有权限,或调用方 uid 的包里有 `com.android.faceunlock` 且它是系统 priv-app(FLAG_SYSTEM + isPrivilegedApp,靠挂到 `/system/priv-app` 保证)」。查 pm 用 `Binder.clearCallingIdentity()` 包起来。
4. **bindService flags(`SenseProvider`)**:绑 SenseService 用 `BIND_AUTO_CREATE | BIND_FOREGROUND_SERVICE | BIND_INCLUDE_CAPABILITIES`。不加 FOREGROUND 的话 `com.android.faceunlock` 一直是后台进程,CAMERA 被 appops 的 foreground-only 限制挡住(录入几秒后开始拒,CameraService 报 "Access for com.android.faceunlock has been restricted");INCLUDE_CAPABILITIES 把 system_server 这头的 CAMERA capability 传过去。

这些类(`SenseProvider`、`SenseHooks`、适配后的 Face*Client 等,共 65 个类)编成一份 **classes4.dex** 塞进 services.jar;AIDL stub(`vendor.aospa.biometrics.face.*`)也在里面。原来的 classes.dex 打完上面的 smali 补丁后换回去,classes2/classes3 原样不动。源码在 `src/java/`。

### 为什么这几处改法和 KLC/上游不一样

Pixel 的 services.jar 是 R8 优化过的(泛型签名/常量/没人用的方法被删,部分方法从 protected 变 public),所以适配类里把泛型基类改成 raw type、内联掉的常量换成数值(`STATE_STARTED=1` 等)、override 改 public、补了 Pixel 版里是抽象的方法。细节见 `src/java/` 的注释和 `co.aospa` 原始工程。新底包(BP1A)相对老底包(AP3A)还多了几个构造器参数(`isMandatoryBiometrics`、`InternalCleanupClient` 的 `int reason` 等),源码里已按新底包适配。

### `ro.face.sense_service=true` 为什么归这个模块

看谁读它:

- 读它的是 `SenseUtils.canUseProvider()`(经 `SenseHooks.getProviders` / `canUseProvider` 调用),在 system_server 里,代码在本模块的 classes4.dex。
- `FaceUnlock.apk` **不读**它。App 只读另一个可选属性 `ro.face.sense_service.camera_id`(没设就用默认相机)。
- 没有本模块的补丁,这个属性设了也没人看。

所以它跟着 services.jar 补丁走,不放进 `faceunlock/app`。

## 改动清单

- **改** `system/framework/services.jar`:换 classes.dex(3 入口 + 57 放行)+ 新增 classes4.dex(Sense 类),classes2/3 不动。
- **追加** `system/build.prop`:`ro.face.sense_service=true`(已有就不重复加)。
- 改完调用 `mark_modified framework/services.jar`,告诉 `stale-boot-image` services 的预编译产物过期了。

`services.jar` 的 oat 产物(`framework/oat/arm64/services.*`)由 **stale-boot-image** 负责删。本模块只换 jar。

> 纠正旧 README(旧工程 `faceunlock/README.md` 第 110 行附近)里的说法:「services.jar 换掉后 oat 校验和对不上,ART 会拒绝并改用 jar 里的 dex,理论上不用删 oat」。这句话不对。V66 实际删了 `oat/arm64/services.*`,原因见 `stale-boot-image` 的 README(留着对不上的 services.odex,system_server 开机会跟着走 memfd 编译)。

## 输入(device.conf / conf.d/faceunlock.conf)

| 变量 | 说明 |
|---|---|
| `APKTOOL_JAR` | apktool 2.12.1(反编译/回编 services.jar;旧版处理不了 A15 dex) |
| `FU_D2J` | dex2jar 2.4.38 的 `d2j-dex2jar.sh`,把底包 framework/services/core-libart 转成编译 classpath |
| `FU_R8` | r8.jar(含 D8)。**用 8.5.35 能和 V66 的 classes4.dex 逐字节一致**;r8 版本直接影响 classes4.dex 的字节,换新版(如 pif-toolchain 的 8.13)产物语义相同、只是 d8 codegen 不同导致字节不同 |
| `FU_JAVA_HOME` | JDK 17(可选,默认系统 java-17) |

构建还要 `java`、`javac`、`debugfs`(从 ART apex 的 ext4 payload 里取 `core-libart.jar`,不用 mount)、`zipalign`、`unzip`。

## 依赖和顺序

- 不依赖其他模块,不 `require_mod`。可以单独启用。
- 要排在 `stale-boot-image` **前面**(它靠本模块打的改动标记决定删什么;它排在前面就看不到标记,本模块会直接报错提醒)。
- `framework.jar` 只当编译 classpath 读,不改;和 `build-consistency-dialog-fix` 谁先谁后都行(它只改 Build 里一个方法体,不影响 classes4.dex 的编译)。
- 功能上要配合 `faceunlock/app`(App 本体、权限 xml)和 `faceunlock/settings-entry`(设置入口)才有完整的人脸解锁。单独启用本模块:services.jar 补丁和属性都在,`SenseProvider` 会注册,但没有 `com.android.faceunlock` 可以绑,设置里也没有入口,人脸用不了,也没有别的副作用。完整的组合表见 `patches/required/tangorpro/tangorpro_bp1a.250505.005/faceunlock/README.md`。

## 适用范围和换底包注意

services.jar 从当前底包现取、现反编译、现回编(classes4.dex 的 classpath 也从当前底包现取),所以换底包会自动适配。但 **R8 优化过的 services.jar,方法名/签名/常量可能变**,补丁有可能打不上。会在这些地方 `die`(不会出一个没功能的包):

- `apply_hooks.py` 打完扫到残留 `USE_BIOMETRIC_INTERNAL` 调用点 > 0,或有 `FAIL` → 某个入口的 smali 形状变了。
- 4 个标记(`SenseHooks.canUseProvider/getProviders/enforceInternal/hasInternal`)在回编后的 smali 里找不到。
- `src/java/` 的适配类编不过(底包的 Face*Client 构造器/方法签名变了)→ 看 javac 报错,对照新底包的 `aidl.Face*Client` 调整源码(主要是构造器参数个数)。
- **定位办法**:单独 `bash src/build_dex.sh <底包system> /tmp/c4.dex` 看编译错误;`java -jar <apktool> d -r services.jar` 后对着 `apply_hooks.py` 的匹配逐条核对 `FaceService$FaceServiceWrapper.smali` 等。

## 踩过的坑(带版本)

- **d8 不能加 `--no-desugaring`**(旧工程 v1):javac 17 对 private 方法引用编成 invoke-custom,不 desugar 时 ART 抛 `IncompatibleClassChangeError`,运行到就崩。`build_dex.sh` 一定 desugar;`check_dex.py` 专门查这类问题,编完自动跑。
- **USE_BIOMETRIC_INTERNAL 是 signature**(v2→v3):privapp 白名单给不了,只能 patch services.jar 放行(57 处)。
- **MANAGE_BIOMETRIC 也是 signature**(v3→v4):两个权限都给不了自签名应用,改成按 `com.android.faceunlock` 系统 priv-app 身份放行。
- **CAMERA foreground-only**(v4→v5):普通 bind 过了 top 缓冲期就被 CameraService 拒,改 `SenseProvider.bindService` 的 flags 解决。
- **R8 封闭世界优化**:某些基类方法若 Pixel 里没有子类覆盖,调用点可能被内联,新加子类的覆盖在那些点不生效 —— 离线查不出,只能上机看日志。
- **classes4.dex 字节依赖 r8 版本**:见上面输入表 `FU_R8`。

## 验证

离线(已在 V66 底包上验证):
- 产物 services.jar 的 **4 份 dex 和 V66 的 services.jar 逐字节相同**(classes.dex 补丁版、classes2/3 原样、classes4 新增;classes4 用 r8 8.5.35 时与 V66 一致)。整个 jar 文件的 sha256 和 V66 不同(zip 里的对齐填充字节不同),条目名、时间戳、压缩方式、CRC 都一致。
- build.prop 里有 `ro.face.sense_service=true`。
- 产物 jar 再反编译,被补丁改的 6 个 smali 与打完补丁的 smali 语义一致(`jarpatch.py smali-equiv`,只差标签名/.line/注释这些无语义的东西)。

上机:
```bash
adb shell getprop ro.face.sense_service        # true
adb shell dumpsys face                          # 有 SenseProvider / 传感器
# logcat 里看 SenseHooks / SenseProvider("SenseProvider registered")
```
