# tango/sepolicy

## 做什么

补齐 Tango 需要的 SELinux 策略和标签。

## 原理

Tango 官方集成包的 `sepolicy/system/{public,private}/tango.te` + `te_macros`,展开成 CIL 追加到 `plat_sepolicy.cil`(`cil_append` 会让 `plat_sepolicy_and_mapping.sha256` 清零,开机时 init 重编策略)。内容:

- 新类型 `tango_prop`(属性)、`tango32_device`(`/dev/tango32` 字符设备)。
- `init` 挂 `binfmt_misc`、写入注册串、从 `/system` 加载内核模块(`system module_load`)。
- 宏 `tango_translated(域, tmpfs类型)` 对 7 个域展开:`zygote`、`app_zygote`、`webview_zygote`、`appdomain`(所有 app)、`crash_dump`、`boringssl_self_test`、`vendor_boringssl_self_test`——每个给 `execmem`(JIT)、读 `tango_prop`、读写 `tango32_device`、读写它自己的 tmpfs 文件(翻译器用 memfd)。
- `plat_property_contexts`:`tango.enabled/debug/log_dir/jit_dump_dir` → `tango_prop`。
- `plat_file_contexts`:`/dev/tango32` → `tango32_device`,`/system_ext/bin/tango_translator` → `system_lib_file`,`/metadata/tango_log` → `tango_log_file`(日志目录,各翻译域可写)。

## 改动清单

`plat_sepolicy.cil`、`plat_property_contexts`、`plat_file_contexts` 各追加一段(带标记,幂等)。

## 输入

无。

## 依赖和顺序

无。

## 适用范围和换底包注意

- 依赖底包 sepolicy 里这些类型存在:`zygote_tmpfs`、`app_zygote_tmpfs`、`webview_zygote_tmpfs`、`appdomain_tmpfs`、`tmpfs`、`binfmt_miscfs`、`mlstrustedobject`、`dev_type`、`property_type`、`system_property_type`。Android 15 的 AOSP 都有。
- 预翻译(`tango_pretranslator`)相关的策略没装,因为那条路要改 framework/installd 源码。
- **取舍**:对 `appdomain` 开 `execmem` 违反 AOSP 的 neverallow,不是编译期错误,因为 init 在设备上用 `secilc -N` 重编(不检查 neverallow)。同时它降低所有 app 的加固。

## 踩过的坑

- 没有在真机上验证;构建机上用 `secilc -m -M true -G -N` 把 base + 本模块 + 34.0 映射 + 原厂 vendor cil 一起编过一遍,无错误。真机上如果出现 `avc: denied` 涉及 tango,看 `adb logcat -b events | grep avc` 补规则。

## 验证

```bash
adb shell ls -Z /dev/tango32          # u:object_r:tango32_device:s0
adb shell getprop -Z tango.enabled    # u:object_r:tango_prop:s0
adb shell dmesg | grep -i 'avc.*tango'
```
