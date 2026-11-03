# tango/core

## 做什么

把 Tango 翻译器装进系统,开机时注册 `binfmt_misc`,让内核把所有 32 位 ARM ELF 交给它。

## 原理

`tango-binfmt.rc` 在 `early-init` 里挂 `binfmt_misc` 并写入注册串:魔数匹配 `\x7fELF` + 32 位 + 小端 + `e_machine=0x28`(ARM),
解释器 `/system_ext/bin/tango_translator`,标志 `POCF`(P 保留 argv[0]、O 打开 binary、C 用被执行文件的凭据、F 立即打开解释器——这样 mount namespace 切换后仍然可用)。
魔数、掩码、标志都照 Tango 官方集成包原样复制。属性 `tango.enabled=1/0` 可在运行时开关(`on property:` 写 `binfmt_misc/tango_translator`)。
`tango.debug` 不是 `off` 时翻译器写日志到 `tango.log_dir`(`/metadata/tango_log`,由 `tango-debug.rc` 在 early-init 建;放 /metadata 是因为它 first-stage 就挂载、开机循环也保留)。

## 改动清单

- `system/system_ext/bin/tango_translator`(0755 0:2000,`system_lib_file`):来自 `$TANGO_PKG/prebuilts/tango_translator`,构建时检查是 aarch64 ELF。
- `system/etc/init/tango-binfmt.rc`(0644,`system_file`);`TANGO_DEBUG` 不是 off 时再加 `tango-debug.rc`。
- `system/build.prop`:`tango.enabled=1`、`tango.debug=<TANGO_DEBUG>`、(调试时)`tango.log_dir`。

## 输入(device.conf / conf.d/tango.conf)

| 变量 | 说明 |
|---|---|
| `TANGO_PKG` | Tango v2.1.0 集成包目录,需要 `prebuilts/tango_translator`。**不进仓库**,默认 `private/tango/pkg` |
| `TANGO_DEBUG` | `off` / `info` / `debug`,默认 `info`(首次上机验证用,稳定后改 `off`) |

## 依赖和顺序

无构建依赖。运行时需要 `tango/kernel-module`(`/dev/tango32`)和 `tango/sepolicy`(权限)才能真正跑翻译。

## 适用范围和换底包注意

- 需要 `system/system_ext/bin` 和 `system/etc/init` 存在。
- 内核要有 `CONFIG_COMPAT`、`CONFIG_BINFMT_MISC`;当前 6.1.112 GKI 都有。
- 翻译器版本和内核模块版本是配套的(都来自同一个集成包);换 Tango 版本时两个一起换。

## 踩过的坑

- Tango 官方 `file_contexts` 给翻译器的标签是 `system_lib_file`(不是 `system_file`),因为它要被各个域当"解释器"映射执行。

## 验证

```bash
adb shell cat /proc/sys/fs/binfmt_misc/tango_translator   # enabled + interpreter /system_ext/bin/tango_translator
adb shell getprop tango.enabled                           # 1
```
