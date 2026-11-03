# gsi-hide/qemu-prop-label

## 做什么

把 `qemu.sf.lcd_density` 的属性 SELinux 标签从 `qemu_sf_lcd_density_prop` 改成 `exported_default_prop`,去掉虚拟机痕迹。

## 原理

`qemu_sf_lcd_density_prop` 在 AOSP 里只有模拟器才会用到。进程的 `/proc/self/maps` 里会映射 `/dev/__properties__/u:object_r:qemu_sf_lcd_density_prop:s0` 这一页属性存储,检测器(Duck Detector)据此判断是虚拟机/模拟器。改成 `exported_default_prop` 后,任何进程的 maps 里都不再有 `qemu_*` 属性页。sepolicy 里的类型定义保留,只是没有属性再关联它。

## 改动清单

- `system/etc/selinux/plat_property_contexts`:映射行 `qemu.sf.lcd_density` 的类型换掉。文件里另有一行注释也提到这个类型名,保留不动。

## 输入 / 依赖

无。

## 换底包注意

只匹配映射行(以 `qemu.sf.lcd_density` 开头的那行)。底包里没有就 log 跳过。

## 踩过的坑

- V60/V64:对这个文件用 `sudo sed -i` 会换 inode,丢 SELinux xattr(V66 里 `plat_property_contexts` 的标签就这样丢成空了)。现在统一用 `edit`(拷出去改完再 `replace` 回去,保留属主/权限/标签)。
- 检查"是否改成功"时一度用全文件 grep,被那条注释误伤,现在只看映射行。

## 验证

不能靠 adb 直接看;用检测器看 maps 里有没有 qemu 标签的属性页,或者 `adb shell cat /system/etc/selinux/plat_property_contexts | grep qemu.sf`。
