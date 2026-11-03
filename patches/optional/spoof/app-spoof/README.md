# spoof/app-spoof — 按 App 伪装 Build.*

**状态:写好了,还没加进 device.conf,没上真机。** 合并步骤见 [pending/README.md](pending/README.md)。

## 为什么

V80 真机报告的两个问题都出在"开机 resetprop 改全局属性"这个做法上(`spoof/global-pif`):

- 属性改了、`/system/build.prop` 文件没改,Hunter 报 6 条"运行时属性与 build.prop 不一致";用 bind 盖文件又被挂载检测报两条强风险(V76–V80 试过 tmpfs、/data、只读重挂,都消不掉)。
- 全局属性连 vendor 进程也看得到:相机 HAL 的联想授权库 `libmorpho_ImageRefiner.so` 初始化时读到 `ro.product.manufacturer=Google` 就 SIGILL,伪装开着时所有拍照都崩。

按 App 伪装 = 系统属性、`/system/build.prop`、挂载表一律保持真机原样,只有名单里的 App 进程看到伪装的 `Build.*`。PixelOS 等 ROM 自带的 PixelPropsUtils / PropImitationHooks 就是这么做的。

## 两种模式(可切换,重启生效)

| 模式 | 做法 | 用途 |
|---|---|---|
| `app`(默认) | framework 钩子按名单改 App 进程里的 `Build.*`;系统属性不动 | 日常;解决相机崩溃和 Hunter 不一致 |
| `global` | 开机 resetprop 改 15 个全局属性(V81 原样;build.prop bind 仍停用) | 按 App 不够用时(比如某个 App 在 native 层读属性)退回 |

```bash
heraldctl spoofmode                 # mode=app|global;effective=这次开机实际是 app / global / off
heraldctl spoofmode global          # 切换(重启生效)
heraldctl spoofapps                 # 名单:default=… / extra=…
heraldctl spoofapps add com.xxx     # 额外加一个(进程名或包名,重启生效)
heraldctl spoofapps remove com.xxx
```
合并 `pending/heraldctl.diff` 后也可以写 `heraldctl spoof mode …` / `heraldctl spoof apps …`。`spoof set/off/get/patch/list/apply` 的格式和回包都不变;`spoof get` 不加字段(接口约定 `HERALD_GLOBAL_PIF_FLAG=` 是最后一行),模式看 `spoofmode` 或 `heraldctl diag`(合并后多 `mode=` 和配置文件那两行)。

## 原理

1. **framework.jar**:新加一份 dex(`com.android.internal.util.PropImitationHooks`,只用公开 API + 反射),插三处调用,都在方法第一条指令前:
   - `ZygoteInit.main` → `PropImitationHooks.init()`:zygote(root)fork App 之前读一次 `/data/system/imitation.conf`,存进静态字段。App 进程继承这份内存,自己不读文件。
   - `Instrumentation.newApplication` 两个重载 → `PropImitationHooks.setProps(context)`:`Application.getProcessName()` 或包名在名单里,就反射改 `Build` / `Build.VERSION` 的静态字段。
   - 配置文件不存在 = 什么都不做(global 模式或伪装关着)。读失败、某个字段不存在都吞掉,不会让 zygote 或 App 起不来。
2. **配置文件** `/data/system/imitation.conf`(root 0600,标签 `imitation_conf_file`):伪装脚本 `herald-global-pif.sh` 在 post-fs-data(zygote 之前)写,每次开机先删再按模式决定写不写。SELinux 只给 zygote 读;普通 App 进不去 `/data/system`。不放 /dev、不用自定义属性(`/dev/__properties__/property_info` 谁都能读)。
3. **名单**:默认 `com.google.android.gms.unstable`(DroidGuard 进程)、`com.android.vending`,装在 `/system/etc/herald_payload/app-spoof/targets.default`;额外的存 `/data/misc/keystore/herald/data/app_spoof_targets`。匹配规则:进程名或包名完全相等(所以 `com.google.android.gms.unstable` 只命中那一个进程,不影响 GMS 其他进程)。
4. **字段**(和 global 模式 resetprop 的 15 个对齐):`FINGERPRINT ID DISPLAY TAGS TYPE BRAND DEVICE MANUFACTURER MODEL PRODUCT`,`VERSION.RELEASE RELEASE_OR_CODENAME INCREMENTAL SECURITY_PATCH DEVICE_INITIAL_SDK_INT`。

## 补丁级别(app 模式)

全局 `ro.build.version.security_patch` / `ro.vendor.build.security_patch` 是 keymint 启动时按 `config.toml [trust] security_patch` 同步的(还有 herald-start.sh 启动前的预对齐)。所以 app 模式下:

- `config.toml [trust] security_patch` 固定为真机日期(`/vendor/build.prop` 文件里的 2025-05-05)→ 全局属性 = 真机 = `/system/build.prop`。
- `os/vendor/boot_patchlevel`(TEE 认证里报的补丁级别)照常跟 profile 日期走(`spoof set` / `patch … all`),强认证需要的"近一年补丁"靠这三项。
- 名单里的 App 由钩子看到 profile 的 `Build.VERSION.SECURITY_PATCH`。
- `spoof patch` 在 app 模式下不再调 keymint 的 `--webui-sync-security-patch`(它会 resetprop 全局属性),回包 `ok patch <日期> via=app-spoof reboot-required`。

**没验证**:keymint 能否接受 `security_patch`(真机日期)和 `os_patchlevel`(profile 日期)不一样。字符串里看不出它要求两者相等;上次的崩溃循环是"属性和 config.toml 的 security_patch 不一致又找不到 resetprop",这里两者一致,不会触发。

## 风险

- **只改 Java 层 `Build.*`**:名单里的进程在 native 层直接读系统属性(`__system_property_get`),拿到的是真机值。DroidGuard 有 native 部分;ROM 自带的同类方案历来只改 Java 层也能过 Play Integrity,强认证靠 keybox,但这台没实测。不行就 `spoofmode global` 退回。
- `com.android.vending` 被伪装后,商店按伪装机型过滤应用;不想要就 `spoofapps` 管不了默认名单——要么改 `targets.default` 重构,要么后续加"排除默认"的命令。
- 钩子类名和插入点是 PixelOS 同款,检测软件如果专门查 framework 里有没有 `PropImitationHooks`,能查到(和 PixelOS 用户一样)。

## 依赖和顺序

`require_mod required/general/attestation-fix`(装插件要它建的 `etc/herald_payload`);改 framework.jar,所以必须排在 `stale-boot-image` 前面。现在的 MODS 里 `stale-boot-image` 在 herald 段前面,合并时要把它挪到 herald 段之后,见 pending/README.md。

## 输入

`APKTOOL_JAR`、`R8_JAR`、`ANDROID_JAR`(device.conf 里已有;钩子只用公开 API,classpath 用 SDK 的 android.jar 就够)。

## 验证(本机)

- 单模块构建:`RAN="herald-core attestation-fix" toolkit/run-module.sh devices/tb321fu-a15/device.conf <小树> spoof/app-spoof`(小树里放 V81 的 framework.jar 和 plat_sepolicy.cil):通过,`smali-equiv` 核对两份被改 dex 回编等价,产物 framework.jar 多一份 classes6.dex。
- 伪装脚本 app / global 两个分支、broker 插件、app 模式的补丁级别:dash 和 busybox sh 下用桩跑过。
- `test-herald-protocol.sh`(合并 pending 补丁后的副本):格式检查全部通过。

## 真机要核对

```bash
heraldctl spoofmode                      # effective=app
adb shell getprop ro.product.model    # 真机 TB321FU
adb shell ls -lZ /data/system/imitation.conf   # shell 应该看不到(Permission denied)
# 伪装开着拍照(微距/普通)不崩;Hunter 不报属性和 build.prop 不一致;Play Integrity 结果
```
