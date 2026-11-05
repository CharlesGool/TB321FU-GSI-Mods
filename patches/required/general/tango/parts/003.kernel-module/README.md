# tango/kernel-module

把 `tango32.ko` 装进 system 并在开机时加载, 让 `/dev/tango32` 出现, 所有翻译进程都能读写.

## 原理

翻译器是 64 位进程, 但要替 32 位程序执行必须由内核按 32 位语义处理的系统调用. `tango32` 模块 (GPL-2.0, 源码在集成包的 `kernel-module/`) 注册 misc 设备 `/dev/tango32`, 通过 ioctl 向 64 位进程提供这些 compat 系统调用. 模块要求 `CONFIG_COMPAT` 和内核 ≥ 5.6.

GKI 开了 `TRIM_UNUSED_KSYMS`, 模块**必须**按设备内核的同一份源码和配置编译, 否则 `insmod` 会因 CRC 或符号不匹配失败.

`files/tango-module.rc` 在 `post-fs-data` 以 `exec_start` 运行 `tango-insmod.sh` (herald 域), 结果写入 `/metadata/tango_log/insmod.txt`, 上一次的保留为 `insmod.prev.txt`. init 等脚本结束才继续, 所以模块在 `zygote-start` 之前已经加载. `files/tango-diag.rc` 在开机完成 30 秒后运行诊断, 模块没加载时再试一次. ueventd 把 `/dev/tango32` 设为 0666 system:system.

V78 到 V80 真机上, init 自己在 `early-init` 执行的 `insmod` 一直没有加载成功, 内核日志也没有失败记录, 原因未查明; herald 域在 `post-fs-data` 加载每次都成功, 所以改用后者.

## 改动清单

- `system/etc/tango/tango32.ko` (0644, `system_file`)
- `system/etc/tango/tango-insmod.sh`, `tango-diag.sh` (0755, `herald_exec`)
- `system/etc/init/tango-module.rc`, `tango-diag.rc`
- `system/etc/ueventd.rc` 追加 `/dev/tango32 0666 system system`

## 输入

| 变量 | 说明 |
| --- | --- |
| `TANGO32_KO` | 按设备内核编好的 `tango32.ko`. **禁止**进仓库 |
| `TANGO_KERNEL_RELEASE` | 目标内核发布串, 当前设备是 `6.1.112-android14-11-gd03cb1d7abcd-ab12592111`. 构建时核对 .ko 的 `vermagic` 第一段, 不一致就停止 |

## 编译 tango32.ko

目标内核是设备当前 boot 里的 GKI `6.1.112-android14-11-gd03cb1d7abcd-ab12592111`, 源码 tag `android14-6.1-2024-11_r1` (commit `d03cb1d7abcd`), `BUILD_NUMBER=12592111`. 使用 Kleaf:

1. 用一个仍存在的分支初始化 Kleaf 工作区, 例如 `repo init -u https://android.googlesource.com/kernel/manifest -b common-android14-6.1-2025-09`, 再把 `common` 切到 tag (月度分支已删除): `git -C common fetch --depth=1 aosp refs/tags/android14-6.1-2024-11_r1`.
2. 在工作区根目录建 `tango32/`, 放入集成包的 `tango32.c`, `tango32.h`, `Makefile` 和 `Kbuild` (内容 `obj-m += tango32.o`), 以及 `BUILD.bazel`:

   ```text
   load("//build/kernel/kleaf:kernel.bzl", "kernel_module")
   kernel_module(name = "tango32", srcs = glob(["*.c", "*.h", "Kbuild"]), outs = ["tango32.ko"], kernel_build = "//common:kernel_aarch64")
   ```

   没有 `Makefile` 时 Kleaf 报 `No targets specified and no makefile found`.
3. `BUILD_NUMBER=12592111 tools/bazel build --config=stamp //common:kernel_aarch64 //tango32:tango32`, 产物在 `bazel-bin/tango32/tango32.ko`.
4. 核对内核 `Image` 的 UTS_RELEASE 和 .ko 的 `vermagic=` 都是上面的发布串.

2026-10-31 的结果: 自编 `Image` 与设备 boot 里的内核同为 35289600 字节, 只有 1165 字节不同, 集中在 `linux_banner`, 构建信息和 BSS 附近; `__ksymtab` 和 `__kcrctab` 区间逐字节相同. `tango32.ko` 为 52688 字节, `vermagic=6.1.112-android14-11-gd03cb1d7abcd-ab12592111 SMP preempt mod_unload modversions aarch64`, 未签名. 模块用到的 31 个内核符号都在 GKI 的 KMI 符号列表里, 没有用到受保护导出, GKI 也没开 `CONFIG_MODULE_SIG_FORCE`, 所以未签名模块可以加载.

## 依赖和适用范围

- 没有构建依赖. 运行时需要 `002.sepolicy` 提供 `module_load` 权限和 `/dev/tango32` 标签, 需要 herald-core 提供 herald 域.
- 换内核 (换原厂 boot) 时**必须**重编 .ko 并修改 `TANGO_KERNEL_RELEASE`. 模块加载失败不影响开机.
- `dmesg | grep tango32` 出现 `Unknown symbol` 或 `disagrees about version of symbol` 时, 编译用的源码或配置与设备内核不一致.

## 验证

```bash
adb shell lsmod | grep tango32
adb shell ls -lZ /dev/tango32          # crw-rw-rw- system system u:object_r:tango32_device:s0
adb shell cat /metadata/tango_log/insmod.txt
```
