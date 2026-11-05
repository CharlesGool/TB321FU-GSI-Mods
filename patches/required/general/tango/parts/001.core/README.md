# tango/core

把 Tango 翻译器装进 system, 开机时注册 `binfmt_misc`, 让内核把所有 32 位 ARM ELF 交给它执行.

## 原理

`files/tango-binfmt.rc` 在 `early-init` 挂载 `binfmt_misc` 并写入注册串: 魔数匹配 `\x7fELF` + 32 位 + 小端 + `e_machine=0x28` (ARM), 解释器 `/system_ext/bin/tango_translator`, 标志 `POCF` (P 保留 argv[0], O 打开 binary, C 用被执行文件的凭据, F 立即打开解释器, 切换 mount namespace 后仍可用). 魔数, 掩码和标志照 Tango 官方集成包原样复制.

属性 `tango.enabled=1/0` 可在运行时开关翻译 (`on property:` 写 `/proc/sys/fs/binfmt_misc/tango_translator`). `tango.debug` 不是 `off` 时, 翻译器把日志写到 `tango.log_dir` (`/metadata/tango_log`, 由 `files/tango-debug.rc` 在 `early-init` 和 `post-fs` 创建). 日志放 `/metadata` 是因为它在 first-stage 就挂载, 开机循环时也保留.

## 改动清单

- `system/system_ext/bin/tango_translator` (0755 0:2000, `system_lib_file`): 来自 `$TANGO_PKG/prebuilts/tango_translator`, 构建时检查是 aarch64 ELF.
- `system/etc/init/tango-binfmt.rc` (0644, `system_file`); `TANGO_DEBUG` 不是 `off` 时另加 `tango-debug.rc`.
- `system/build.prop`: `tango.enabled=1`, `tango.debug=<TANGO_DEBUG>`, `TANGO_DEBUG` 不是 `off` 时加 `tango.log_dir=/metadata/tango_log`.

## 输入

| 变量 | 说明 |
| --- | --- |
| `TANGO_PKG` | Tango v2.1.0 集成包目录, 需要 `prebuilts/tango_translator`. **禁止**进仓库 |
| `TANGO_DEBUG` | `off`, `info` 或 `debug`. 未设置时按 `off` 处理 |

## 依赖和适用范围

- 没有构建依赖. 运行时需要 `003.kernel-module` 提供 `/dev/tango32`, `002.sepolicy` 提供权限.
- 底包需要有 `system/system_ext/bin` 和 `system/etc/init`; 内核需要 `CONFIG_COMPAT` 和 `CONFIG_BINFMT_MISC` (6.1.112 GKI 都有).
- 翻译器和内核模块来自同一个集成包, 换 Tango 版本时两者一起换.
- Tango 官方 `file_contexts` 给翻译器的标签是 `system_lib_file`, 不是 `system_file`, 因为各个域都要把它当解释器映射执行.

## 验证

```bash
adb shell cat /proc/sys/fs/binfmt_misc/tango_translator   # enabled, interpreter /system_ext/bin/tango_translator
adb shell getprop tango.enabled                           # 1
```
