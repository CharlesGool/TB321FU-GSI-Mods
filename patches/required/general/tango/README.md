# tango: 32 位 APK 支持

TB321FU-GSI-Mods 补丁 `required/general/tango` 的说明: 把 [Tango](https://www.amanieusystems.com/) (Amanieu Systems 的 ARM32→ARM64 二进制翻译器) 集成进 system 镜像, 让 TB321FU 免 root 安装和运行 32 位 APK. 依赖, 版本和运行时命令见 [patch.conf](patch.conf), 每个部分的原理见各部分的 README.

TB321FU 的 SoC (骁龙 8 Gen 3) 没有 AArch32 核, 32 位 ARM 程序不能直接执行. Tango 是进程级翻译, 不是 native bridge: `binfmt_misc` 把每个 32 位 ARM ELF 交给静态 arm64 程序 `tango_translator` 执行; 需要内核按 32 位语义处理的 compat 系统调用, 由内核模块 `tango32` 通过 `/dev/tango32` 提供. 核心集成不改 framework.

## 部分

5 个部分在 `parts/NNN.<部分>/` 下按编号顺序执行, 整个补丁只能一起打或一起不打.

| 部分 | 作用 | 构建输入 |
| --- | --- | --- |
| [001.core](parts/001.core/README.md) | 装 `tango_translator`, 开机注册 `binfmt_misc`, 写 `tango.*` 属性 | `TANGO_PKG` |
| [002.sepolicy](parts/002.sepolicy/README.md) | 新类型, 翻译进程的 `execmem` 和 `/dev/tango32` 权限, 属性和文件标签 | 无 |
| [003.kernel-module](parts/003.kernel-module/README.md) | 装 `tango32.ko`, `post-fs-data` 加载, `/dev/tango32` 设为 0666 | `TANGO32_KO`, `TANGO_KERNEL_RELEASE` |
| [004.vendor-lib32](parts/004.vendor-lib32/README.md) | 用 overlay 给 `/vendor/lib` 补 32 位 Adreno 和 gralloc 库 | `XIAOMI_LIB32_DIR`, `STOCK_VENDOR_IMG` |
| [005.zygote32](parts/005.zygote32/README.md) | 声明 32 位 ABI, 起 32 位 zygote, 接管 vendor 32 位自检, 关闭 WALT 32 位自检, 开机保险和日志导出 | `STOCK_VENDOR_IMG` |

## 开机顺序

同一个 trigger 内, init 按 `init.rc` 及其 import, `/system/etc/init`, `/vendor/etc/init` 的顺序解析 rc.

| 阶段 | 动作 | 部分 |
| --- | --- | --- |
| `early-init` | 挂载 `binfmt_misc` 并注册翻译器; 建 `/metadata/tango_log` (`TANGO_DEBUG` 不是 `off` 时) | core |
| `early-init` | vendor 32 位 BoringSSL 自检改跑 64 位程序 | zygote32 |
| `post-fs` | 把 32 位 GPU 库 overlay 到 `/vendor/lib` | vendor-lib32 |
| `post-fs-data` | 以 herald 域 `insmod tango32.ko` | kernel-module |
| `post-fs-data` | 开机保险: 关 WALT 32 位自检, 确认模块, 置 `tango.zygote32=1` | zygote32 |
| `zygote-start` | `tango.zygote32=1` 时启动 `tango_zygote32` (第一个靠翻译运行的进程) | zygote32 |

## 验证

```bash
adb shell cat /proc/sys/fs/binfmt_misc/tango_translator   # enabled, interpreter /system_ext/bin/tango_translator
adb shell ls -lZ /dev/tango32                             # crw-rw-rw- system system u:object_r:tango32_device:s0
adb shell getprop ro.product.cpu.abilist                  # arm64-v8a,armeabi-v7a,armeabi
adb shell ps -A | grep zygote                             # zygote64 和 32 位 zygote 都在
adb shell heraldctl tango status
```

出问题时先看 `getprop sys.boot.reason.last`, 再看 `/metadata/tango_log` 和 `dmesg | grep -iE 'tango|avc|boringssl|walt'`.

## 取舍

- **`execmem`**: Tango 的 JIT 要求所有被翻译的进程域 (zygote 和全部 app 域) 有 `execmem`. 这是官方策略, 但违反 AOSP 对 app 的 neverallow, 降低所有 app 的加固.
- **WALT 自检**: `panic_on_walt_bug=0` 关闭的是联想 `sched-walt.ko` 的整套 WALT-BUG 检查, 不只 32 位那条.
- **32 位 GPU 栈**: 来自小米 14 Ultra 的 `V@0762.4`, 设备 64 位 Adreno 是 `V@0762.28`; 与内核 KGSL 的兼容性没有单独验证.
- **ART GC**: `ro.dalvik.vm.enable_uffd_gc=false` 让 64 位 ART 也改用 CC GC; 改动后第一次开机 odrefresh 重编启动镜像.
- **预翻译**: 没做. 每个 32 位库首次运行时较慢, 之后有缓存.

调研过程, 与小米 14 Ultra 和一加 12 的对照, 以及整机重启的真因见 [调研记录](https://github.com/CharlesGool/tango-porting-guide/blob/main/doc/research.md).

## 授权

`tango_translator`, Tango 集成包, `tango32.ko` 和小米的 32 位库都**禁止**进仓库, 也**禁止**放进分发给他人的刷机包. 仓库只放小米库的文件名和 SHA-256 清单. 详见 [第三方声明](https://github.com/CharlesGool/tb321fu-tango-patch/blob/main/doc/THIRD_PARTY_NOTICES.md).
