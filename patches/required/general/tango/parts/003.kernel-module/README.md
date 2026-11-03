# tango/kernel-module

## 做什么

把 `tango32.ko` 装进系统并在开机加载,让 `/dev/tango32` 出现、所有翻译进程可读写。

## 原理

Tango 的翻译器是 64 位进程,但要替 32 位程序执行某些必须由内核按 32 位语义处理的系统调用。`tango32` 模块(GPL-2.0,源码在集成包 `kernel-module/`)
注册 misc 设备 `/dev/tango32`,通过 ioctl 向 64 位进程暴露这些 compat 系统调用。要求 `CONFIG_COMPAT`(当前内核有),内核 ≥ 5.6。
模块里用到的内核符号都在 Android 5.15+ 的 KMI 符号列表里,但 GKI 开了 `TRIM_UNUSED_KSYMS`,**必须按设备内核同源码、同配置编,否则 `insmod` 因 CRC / 符号对不上失败**。

`tango-module.rc` 在 `on early-init` 里(要赶在第一个 32 位进程之前) `insmod /system/etc/tango/tango32.ko`(SELinux 的 `system module_load` 由 `tango/sepolicy` 提供);ueventd 给 `/dev/tango32` 0666 system:system。

## 改动清单

- `system/etc/tango/tango32.ko`(0644,`system_file`)
- `system/etc/init/tango-module.rc`
- `system/etc/ueventd.rc` 追加 `/dev/tango32 0666 system system`

## 输入

| 变量 | 说明 |
|---|---|
| `TANGO32_KO` | 按设备内核编好的 `tango32.ko`。**不进仓库**,默认 `private/tango/tango32.ko` |
| `TANGO_KERNEL_RELEASE` | 目标内核发布串(默认 `6.1.112-android14-11-gd03cb1d7abcd-ab12592111`)。构建时核对 .ko 的 vermagic 第一段,不一致就停 |

### 怎么编 tango32.ko(在构建主机上,Kleaf)

目标内核 = 设备当前 boot 里的 GKI:`6.1.112-android14-11-gd03cb1d7abcd-ab12592111`,源码 tag `android14-6.1-2024-11_r1`(commit `d03cb1d7abcd` 对上),`BUILD_NUMBER=12592111`。

1. 拿一份 Kleaf 工作区(`repo init -u https://android.googlesource.com/kernel/manifest -b common-android14-6.1-2025-09` 之类的活分支引导),把 `common` 切到 `refs/tags/android14-6.1-2024-11_r1`(月度分支被删,按 tag 取:`git -C common fetch --depth=1 aosp refs/tags/...`)。
2. 工作区根下建 `tango32/`,放入 `tango32.c`、`tango32.h`,`Kbuild` 内容 `obj-m += tango32.o`,`BUILD.bazel`:
   ```
   load("//build/kernel/kleaf:kernel.bzl", "kernel_module")
   kernel_module(name = "tango32", srcs = glob(["*.c", "*.h", "Kbuild"]), outs = ["tango32.ko"], kernel_build = "//common:kernel_aarch64")
   ```
3. `BUILD_NUMBER=12592111 tools/bazel build --config=stamp //common:kernel_aarch64 //tango32:tango32`;产物 `bazel-bin/tango32/tango32.ko`。
4. 核对:先看内核 `Image` 的 UTS_RELEASE 是不是上面那串;再看 .ko 的 `vermagic=`。

2026-10-31 实际结果:自编 `Image` 与设备 boot 里的内核同样 35289600 字节,只有 1165 字节不同,集中在 `linux_banner`/构建信息和 BSS 附近;
`__ksymtab`(0x15d9910–0x15e2e5c)和 `__kcrctab`(0x15f0d10–0x15f3ed4)区间逐字节相同,所以符号表和 CRC 与设备内核一致,模块的 modversions 不会对不上。
`tango32.ko` 52688 字节,`vermagic=6.1.112-android14-11-gd03cb1d7abcd-ab12592111 SMP preempt mod_unload modversions aarch64`,没签名(构建机上没有 signing_key.pem,GKI 不强制)。
Kleaf 的 `kernel_module` 要求模块目录里有 `Makefile`(用集成包自带的那个,不是单 `Kbuild`),否则报 `No targets specified and no makefile found`。

## 依赖和顺序

无构建依赖。需要 `tango/sepolicy` 才有 `module_load` 权限和 `/dev/tango32` 标签。

## 适用范围和换底包注意

- 换内核(换原厂 boot):必须重编 .ko,`TANGO_KERNEL_RELEASE` 改成新串。模块没有也只是 insmod 失败,不影响启动。
- 模块没签名;`MODULE_SIG_PROTECT=y` 的 GKI 允许加载不用受保护符号的未签名模块,`CONFIG_MODULE_SIG_FORCE` 没开。

## 踩过的坑

- 还没有真机验证。如果 `dmesg | grep tango32` 出现 `Unknown symbol` / `disagrees about version of symbol`,说明编译用的源码或配置与设备 boot 内核不一致。

## 验证

```bash
adb shell lsmod | grep tango32
adb shell ls -lZ /dev/tango32          # crw-rw-rw- system system u:object_r:tango32_device:s0
adb shell dmesg | grep -i tango
```
