# boot — 补丁 boot 的落地(assemble)

boot 里的改动**按功能**放在各自的组里,这里只有把它们落地的一步:

| 改动 | 所在模块 | 做什么 |
|---|---|---|
| 内核从第一刻起就是 SELinux Enforcing | [`selinux/fix`](../../patches/required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/fix/README.md) | 贡献者:内核命令行加 `enforcing=1 selinux=1` |
| `/proc/version` 里的编译者不再是 `build-user@build-host` | [`kernel-builder-string`](../../patches/required/general/boot-kernel/kernel-builder-string/README.md) | 贡献者:内核里等长替换成 `androidbld@abfarmhost` |

| 模块 | 做什么 | 能单独关吗 |
|---|---|---|
| [`assemble`](../../patches/required/general/boot-kernel/boot-assemble/README.md) | 汇总上面登记的改动,一次性改原厂 `boot.img`、用同一把 testkey 按原参数重签,输出 `boot.img` | 不能关(关了就没有补丁 boot);零贡献者时原样输出原厂 boot |

这几个补丁和别的补丁一样由 `toolkit/build.sh` 按 `device.conf` 的 `MODS` 执行,拿到的环境里没有 `TREE` / `SYS`,生成的 `boot.img` 放在 `$FW_OUT`。主 vbmeta 不用跟着改(boot 是 chain descriptor,只钉公钥);toolkit/build.sh 在全部补丁之后调 `toolkit/avb_resign.sh main`,见 [docs/AVB-RESIGN.md](../AVB-RESIGN.md)。

## 顺序

```
selinux/kernel-enforcing        只登记
kernel-builder-string    只登记
boot-assemble                     必须排在所有贡献者后面;读原厂 boot,输出 $FW_OUT/boot.img
```

贡献者只往 `boot` 这个产物登记自己那份,不碰 boot.img,所以只启用其中一个也能工作。登记格式由 assemble 定义,见 [assemble/README.md](../../patches/required/general/boot-kernel/boot-assemble/README.md)。

## 为什么必须从当前固件的 boot 现打

boot 里装的是 GKI 内核本体。vendor_boot / vendor_dlkm 里的内核模块是对着这颗内核的 KMI 和 vermagic 编的。**换原厂固件后,补丁 boot 必须对着新固件的 boot.img 重打,不能复用旧的**。详见 [assemble/README.md](../../patches/required/general/boot-kernel/boot-assemble/README.md) 的"换固件必须重打"。

## 整组独立发布

可以:拿 `patches/required/general/boot-kernel/boot-assemble/` + 两个贡献者补丁 + `toolkit/`(`build.sh`、`lib/`、`avb/`)即可。不含私有文件:签名用的 testkey 私钥和原厂 boot.img 由使用者自己提供,路径在 `firmware.conf` 里设。
