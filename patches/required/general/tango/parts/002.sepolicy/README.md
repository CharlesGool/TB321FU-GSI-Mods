# tango/sepolicy

补齐 Tango 需要的 SELinux 策略和标签.

## 原理

把 Tango 官方集成包的 `sepolicy/system/{public,private}/tango.te` 和 `te_macros` 展开成 CIL (`tango.cil`), 追加到 `plat_sepolicy.cil`. 追加后 `plat_sepolicy_and_mapping.sha256` 不再匹配, 开机时 init 在设备上重编策略. 内容:

- 新类型 `tango_prop` (属性), `tango32_device` (`/dev/tango32` 字符设备), `tango_log_file` (日志目录).
- `init` 可以挂载 `binfmt_misc`, 写入注册串, 从 `/system` 加载内核模块 (`system module_load`).
- 宏 `tango_translated(域, tmpfs类型)` 对 7 个域展开: `zygote`, `app_zygote`, `webview_zygote`, `appdomain`, `crash_dump`, `boringssl_self_test`, `vendor_boringssl_self_test`. 每个域获得 `execmem` (JIT), 读 `tango_prop`, 读写 `tango32_device`, 读写自己的 tmpfs 文件 (翻译器使用 memfd).
- `zygote` 可以读 `proc_security` (翻译器读取 `randomize_va_space`).
- `plat_property_contexts`: `tango.enabled`, `tango.debug`, `tango.log_dir`, `tango.jit_dump_dir` → `tango_prop`.
- `plat_file_contexts`: `/dev/tango32` → `tango32_device`, `/system_ext/bin/tango_translator` → `system_lib_file`, `/metadata/tango_log` → `tango_log_file`.

## 改动清单

`plat_sepolicy.cil`, `plat_property_contexts`, `plat_file_contexts` 各追加一段, 带标记, 重复执行不会重复追加.

## 输入

无.

## 依赖和适用范围

- 没有构建依赖.
- 底包 sepolicy 需要有这些类型: `zygote_tmpfs`, `app_zygote_tmpfs`, `webview_zygote_tmpfs`, `appdomain_tmpfs`, `tmpfs`, `binfmt_miscfs`, `mlstrustedobject`, `dev_type`, `property_type`, `system_property_type`. Android 15 的 AOSP 都有.
- 没装预翻译 (`tango_pretranslator`) 的策略, 因为预翻译需要修改 framework 和 installd 源码.
- 对 `appdomain` 开 `execmem` 违反 AOSP 的 neverallow. 构建不会报错, 因为 init 在设备上用 `secilc -N` 重编 (不检查 neverallow).

## 验证

V883 真机 (2026-10-31) 带全部 5 个部分运行 32 位 APK 正常. 构建机上用 `secilc -m -M true -G -N` 把底包策略, 本部分, 34.0 映射和原厂 vendor CIL 一起编译通过.

```bash
adb shell ls -Z /dev/tango32          # u:object_r:tango32_device:s0
adb shell getprop -Z tango.enabled    # u:object_r:tango_prop:s0
adb shell dmesg | grep -i 'avc.*tango'
```
