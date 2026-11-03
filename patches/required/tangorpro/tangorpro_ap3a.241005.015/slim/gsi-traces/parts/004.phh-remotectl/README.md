# slim/gsi-traces/phh-remotectl

## 做什么

删 `bin/phh-remotectl.sh` 和 `etc/init/phh-remotectl.rc`。

## 原理

phh 的远程调试功能:`persist.sys.phh.remote=true` 时,`phh-remotectl.rc` 把 adb 的 TCP 端口开到 5555、重启 adbd、启动 `phh-remotectl` 服务,服务脚本用 dropbear 的 `dbclient` 反向隧道到 `android-remote.phh.me`(一个第三方服务器)。

- 属性不设就不会触发,默认不跑。
- 它指定的 SELinux 域 `u:r:phhsu_daemon:s0` 在这个底包里根本不存在(Mystic 去掉了 phh 的 sepolicy),真触发也起不来。
- 删掉后少一个会往外连的入口。

## 改动清单

- 删 `bin/phh-remotectl.sh`、`etc/init/phh-remotectl.rc`。`plat_file_contexts` 里留着的 `phh-remotectl.sh` 条目无害。

## 输入 / 依赖

无。

## 换底包注意

别的 GSI 没有就跳过。

## 验证

`adb shell ls /system/bin/phh-remotectl.sh` 不存在;`adb shell getprop init.svc.phh-remotectl` 为空。
