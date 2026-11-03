# tango — 32 位 APK 支持(Tango 二进制翻译)

> 一个补丁(`tango`),内部 5 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`tango`),内部 5 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

TB321FU 的 SoC(骁龙 8 Gen 3)CPU 没有 AArch32,32 位 ARM 程序直接 exec 会失败。这一组把 [Tango](https://www.amanieusystems.com/)(Amanieu Systems 的 ARM32→ARM64 二进制翻译器)集成进系统,
装完 32 位 APK 能安装、能运行,免 root。

## 原理一句话

Tango 不是 native bridge,而是**进程级翻译**:`binfmt_misc` 注册一个 handler,每个 32 位 ARM ELF(包括 32 位 zygote、32 位 app 进程)被内核当作"解释器 = tango_translator"来启动;
翻译器是静态 arm64 程序,自己翻译指令;需要内核处理的 32 位 compat 系统调用,由内核模块 `tango32` 通过 `/dev/tango32` 暴露给 64 位的翻译器进程(模块依赖内核的 `CONFIG_COMPAT`,官方要求内核 ≥ 5.6)。
Android 15 的核心集成**不需要改 framework**:翻译器 + binfmt rc + SELinux + 一个 32 位 zygote 就够。

## 模块

| 部分 | 做什么 | 需要的输入 | 单独装有没有用 |
|---|---|---|---|
| [core](parts/001.core/) | 装 `tango_translator`,开机注册 binfmt_misc,`tango.*` 属性 | `TANGO_PKG`(集成包) | 单装:内核会把 32 位 ELF 交给翻译器,但没有内核模块和策略,翻译器会失败 |
| [sepolicy](parts/002.sepolicy/) | 两个新类型 + 翻译进程的 execmem / `/dev/tango32` 权限 + 属性/文件标签 | 无 | 单装无副作用,也没用 |
| [kernel-module](parts/003.kernel-module/) | 装 `tango32.ko`,开机 `insmod`,ueventd 开 `/dev/tango32` 0666 | `TANGO32_KO`(按设备内核编) | 单装无副作用(模块没人用) |
| [vendor-lib32](parts/004.vendor-lib32/) | 给 `/vendor/lib` 补小米 14 Ultra 的 32 位 Adreno/gralloc 栈(overlay) | `XIAOMI_LIB32_DIR` | 单装无副作用,64 位不受影响 |
| [zygote32](parts/005.zygote32/) | 声明 32 位 ABI,自带一个 `zygote_secondary` 服务(不改 `ro.zygote`,照小米 14 Ultra 的做法),ART 统一 CC GC,开机保险 + 崩溃现场导出 | `STOCK_VENDOR_IMG`(扫 rc) | 单装能开机,但翻译链不全时保险会直接回退纯 64 位 |

**模块互相不依赖,构建都能过**;功能上要全部装齐才能跑 32 位 APK。建议分两阶段:

1. 阶段 1:`core` + `sepolicy` + `kernel-module` + `vendor-lib32`。刷完用 adb 跑一个 32 位 ELF,验证内核模块、翻译器、策略。阶段 1 不声明 32 位 ABI,不会触发下面"开机早期"说的那些自检,开机风险最小。
2. 阶段 2:阶段 1 通过后再打开 `zygote32`,装 32 位 APK 试 GL / Vulkan 界面。

### 阶段 1 怎么验证(不需要 32 位 GPU 栈)

```bash
adb shell cat /proc/sys/fs/binfmt_misc/tango_translator      # enabled, interpreter /system_ext/bin/tango_translator
adb shell lsmod | grep tango32 ; adb shell ls -lZ /dev/tango32
adb shell /system/bin/app_process32                          # 经 Tango 翻译跑一个 32 位程序,应打印 "app_process: ... no class name or --zygote supplied" 之类的用法提示
adb shell ls /metadata/tango_log                             # TANGO_DEBUG≠off 时翻译器的日志
adb shell dmesg | grep -iE 'tango|avc'                       # 有拒绝就按 avc 补规则
```

## 参照小米 14 Ultra(同 SM8650,官方集成 Tango)

2026-10-31 把 xiaomi.eu OS2.0.213(Android 15)的 super 解开逐项对照,详见工程 `doc/tango-research.md` 第 4 节。要点:翻译器、binfmt 注册串、内核模块源码、SELinux 规则都和我们一致;
差异在两处,已改成小米的做法:**不改 `ro.zygote`**(自带 `zygote_secondary` 服务,`zygote32/files/tango-zygote32.rc`)和 **`ro.dalvik.vm.enable_uffd_gc=false`**(32 位 ART 只能用 CC GC,启动镜像要按 CC 编)。
小米还做了装机预翻译(要改 framework 源码)和 framework 侧的懒加载,我们不做。

## 开机早期:哪些东西会在 Tango 就绪前碰 32 位

V68 带全部五个模块刷机后卡第一屏开机循环,`sys.boot.reason.last` = `reboot,boringssl-self-check-failed`。真正的原因是**联想 vendor 的 32 位 BoringSSL 自检**:
`ro.product.cpu.abilist32` 一非空,vendor 的 `boringssl_self_test.rc` 就在 `early-init` 跑 `/vendor/bin/boringssl_self_test32`,而联想 vendor 只有 64 位版本,这个文件不存在,服务起不来就触发 `reboot_on_failure`。和 Tango 无关,翻译器再好也救不了。
(当初的分析以为是 system 的 32 位自检跑在 `tango32.ko` 加载之前;但 A15 `init.rc` 里 system 的自检没有 `reboot_on_failure`,不会报这个重启原因。)

开机时 Tango 相关动作的先后(同一个 trigger 内按 rc 解析顺序:`init.rc` 及其 import → `/system/etc/init` → `/vendor/etc/init`):

| 阶段 | 动作 | 谁管 |
|---|---|---|
| `early-init` | 挂 binfmt_misc 并注册翻译器 | core |
| `early-init` | `insmod tango32.ko` | kernel-module |
| `early-init` | vendor 32 位自检 → 换成 `/vendor/bin/boringssl_self_test64` | zygote32 |
| `init` | system 32 位自检:`ro.zygote` 保持 `zygote64` 后不再触发(rc 里的 override 只是兜底) | zygote32 |
| `post-fs` | overlay 32 位 GPU 库到 `/vendor/lib` | vendor-lib32 |
| `post-fs-data` | `insmod tango32.ko`(herald 域,exec_start);保险脚本检查模块、崩溃标记,放行则置 `tango.zygote32=1` | kernel-module / zygote32 |
| `zygote-start` | `tango.zygote32=1` 才起 `zygote_secondary`(第一个真正靠 Tango 翻译的进程) | zygote32 |

所以现在:
- 第一屏这一关只剩 `zygote32` 声明 ABI 引出的自检,已全部接管;构建时 `zygote32/check_vendor32.py` 扫原厂 vendor,再有同类服务就停。
- Tango 本身坏了(模块没加载、策略拒绝、翻译器崩),最先出事的是 `zygote_secondary`。`zygote32` 删了它的 `onrestart restart zygote`,所以结果是"系统能进、32 位 app 打不开",不会卡开机动画。
- 出问题时先看 `sys.boot.reason.last`,再看 `/metadata/tango_log` 和 `dmesg | grep -iE 'tango|avc|boringssl'`。

## 授权与不进仓库的文件

- Tango 的个人用途免费、商用要授权;EULA 禁止复制/分发/转售/反编译。`tango_translator`、集成包都**不进仓库**,放 `private/`(已 gitignore),也**不要放进给别人的刷机包**。
- 评估许可写"连续运行最多 4 小时",和个人授权的关系 EULA 没说清;长期使用请联系 info@amanieusystems.com 确认。
- 小米的 32 位库同理,版权属于小米/高通,只在本机用,仓库里只放文件名+sha256 清单。

## 真机结果

V883-PIF(2026-10-31)真机通过:32 位 APK 正常运行。V68–V882 的失败原因和修法见工程 `doc/tango-research.md`(0 节是最终做法一页表,4d 节是真因)。
真因一句话:联想 `vendor_boot` 里的 WALT 调度器模块对"带 TIF_32BIT 的任务必须在 32 位核上"做自检并 `BUG()`,这台机器没有 32 位核,Tango 内核模块临时标记任务为 32 位就触发;`zygote32` 的保险脚本放行前把 `/proc/sys/walt/panic_on_walt_bug` 写 0 关掉它。

## 取舍与风险

- **`execmem` 放宽**:Tango 的 JIT 需要所有被翻译的进程(zygote、所有 app 域)有 `execmem`。这是官方策略,但 AOSP 本来对 app 禁止它,实际降低了所有 app 的加固。和 [selinux](../../required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/)、[gsi-hide](../../required/general/bug-fix/gsi-hide/) 的加固方向冲突,只对"要跑 32 位 APK"的需求值得。
- **32 位 GPU 栈来自别的设备**:原厂 vendor 里没有 32 位 Adreno。用的是小米 14 Ultra(同 SM8650)Eu 固件的 32 位 Adreno `V@0762.4`,而设备 64 位 Adreno 是 `V@0762.28`。小米自己也是 32 位 0762.4 配 64 位 0762.30/.36,用户态组合可行,但 KGSL 版本差异没验证。
- **32 位 ART 启动镜像**:Tango 禁用 userfaultfd,32 位 ART 走 CC GC,而 odrefresh 默认按 CMC 编 32 位启动镜像,对不上(V79 真机日志)。`zygote32` 设 `ro.dalvik.vm.enable_uffd_gc=false` 让 64/32 位都用 CC(小米同样设置),改动后第一次开机重编一次。
- **WALT 其它自检被静默**:`panic_on_walt_bug=0` 关掉的是整套 WALT-BUG 机制,不只 32 位那条。更干净的做法是像一加 12 那样给 `sched-walt.ko` 补"32 位核掩码为空就跳过"再重打 `vendor_boot`,目前没做。
- 没做预翻译(build-time/on-device pretranslation):首次运行每个 32 位库会慢,之后有缓存。on-device 预翻译要改 frameworks/base 和 installd 源码,二进制 GSI 做不了。
