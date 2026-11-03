# slim/gsi-traces/phh-keylayouts

## 做什么

删 `/system/phh` 下 30 项:各厂商的按键布局 `*.kl`(三星、小米、一加、摩托罗拉、OPPO……)、NFC 配置 `libnfc-nci-*.conf`、`gome/`、`huawei/`、`umidigi/` 子目录。**保留 `phh/empty`**(一个 0 字节的文件)。

## 原理

这些文件只被 `rw-system.sh` 里按厂商/机型匹配的分支用:先把 `/system/usr/keylayout` 拷到 tmpfs,再把对应厂商的布局拷进去,最后 bind 回去。TB321FU 的 vendor 指纹是 `Lenovo/TB321FU/…`,约 80 个分支只有一个 Lenovo 的会匹配,而且它还要求有 `/sys/devices/virtual/touch/tp_dev/gesture_on`(手机触摸屏的手势节点,平板没有)。所以这些文件在我们机型上没人读。

**为什么留 `empty`**:`rw-system.sh` 第 545、546 行无条件地执行
`mount -o bind /system/phh/empty /vendor/lib/libpdx_default_transport.so`(以及 lib64 版),把一个空文件盖到 vendor 的这个库上——没有机型判断。`/system/phh/empty` 要是没了,这个 mount 失败,vendor 的库就不再被盖住,行为和以前(V1 到 V66 都是盖住的)不一样。保持原样,所以只删别的、留这一个文件。

## 改动清单

- 删 `phh/` 下除 `empty` 以外的所有项。

## 输入 / 依赖

无。

## 换底包注意

- 底包里没有 `phh/empty` 就失败(说明不是同款 phh 布局,先看看有没有别的东西依赖)。
- 别的 GSI 的 `rw-system.sh` 如果有新的无条件引用,要把对应文件加进保留名单。

## 验证

```bash
adb shell ls -A /system/phh          # 只有 empty
adb shell ls /vendor/lib64/libpdx_default_transport.so && adb shell stat -c %s /vendor/lib64/libpdx_default_transport.so   # 看是否仍被盖成 0 字节(和删之前一致)
```
