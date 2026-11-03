# kernel-builder-string — 内核编译者字符串

## 做什么

把内核里的编译者 `build-user@build-host` 改成 `androidbld@abfarmhost`,于是 `/proc/version` 看起来像 Google 构建农场编的。这是贡献者模块:只把替换规则登记到产物 `boot`,真正改 boot.img 的是 [boot-assemble](../boot-assemble/README.md)(登记格式也在那里,类型 `replace`)。

## 原理

内核镜像里有三处这个字符串:`linux_banner`(就是 `/proc/version` 的内容)和两份带格式的版本串。`build-user@build-host` 是 Kleaf 构建的默认值,本地或第三方用 Kleaf 编的内核也是这个值;改成 Google 构建农场的写法。这条规则从 V7.4 起一直这么用,V47 重打时用 V7.4 的原始/补丁两颗 boot 逐字节比对过替换规则。

两个字符串都是 21 字节,等长替换,内核里其它东西的偏移都不动。assemble 只在内核区域 `[4096, 4096 + kernel_size)` 里找,命中 0 处就失败(说明内核是压缩的,或者编译者本来就不是这个,要人工看)。

这一条单独有没有被哪个检测用到,没有单独验证过(V47 实验是 cmdline 和字符串两处一起改的)。

## 改动清单

不碰 boot.img,只登记一条 `replace` 记录。启用后(经 assemble)内核里 3 处各 21 字节,每处有 16 字节不同。

## 输入

| 变量 | 说明 |
|---|---|
| `FW_BOOT_KBUILD_FROM` | 要替换的原串,TB321FU 是 `build-user@build-host` |
| `FW_BOOT_KBUILD_TO` | 替换成的串,`androidbld@abfarmhost`。必须和 FROM 一样长,否则本模块报错 |

## 依赖和顺序

排在 `boot-assemble` 前面。和 `selinux/kernel-enforcing` 互不依赖。

## 适用范围和换底包注意

换固件后内核里没有这个串(换了编译者、或内核是压缩的),assemble 会失败,先看新内核 `/proc/version` 那串再改 `FW_BOOT_KBUILD_FROM`。内核区域外另有的同样字符串不会被动。换固件后补丁 boot 必须重打,见 [assemble](../boot-assemble/README.md)。

## 验证

刷机后:

```bash
adb shell cat /proc/version      # 里面是 (androidbld@abfarmhost)
```

构建时:只启用本模块 + assemble,生成的 boot 里 cmdline 仍为空、内核里 3 处都已替换(2026-10-31 实测)。
