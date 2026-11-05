# tango/zygote32

声明系统支持 32 位 ABI 并启动 32 位 zygote, 让 32 位 APK 能安装和启动. 同时处理声明 32 位 ABI 带来的开机问题: vendor 32 位自检, ART GC 类型, 联想 WALT 调度器的 32 位自检, 以及开机保险和日志导出.

## 32 位 zygote

做法参照小米 14 Ultra (对照见[调研记录](https://github.com/CharlesGool/tango-porting-guide/blob/main/doc/research.md#小米-14-ultra)):

- **不改 `ro.zygote`**, 保持 vendor 的 `zygote64`. init 因此不 import `init.zygote64_32.rc` 和 `init.boringssl.zygote64_32.rc`, system 的两个 32 位自检不会触发.
- `files/tango-zygote32.rc` 定义服务 `tango_zygote32`, 命令行抄自原版 `zygote_secondary`, 改三处:
  - 服务名不用 `zygote_secondary`: 原版 `init.rc` 的 `on zygote-start` 无条件 `start zygote_secondary`, `disabled` 挡不住.
  - 去掉 `onrestart restart zygote`: 32 位 zygote 崩溃只影响 32 位 app, 不连带重启 system_server.
  - 加 `disabled`, 由 `on zygote-start && property:tango.zygote32=1` 启动.
- socket 名**必须**仍是 `zygote_secondary`, system_server 的 `ZygoteProcess` 按 socket 名连接.
- `ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi`, `abilist32=armeabi-v7a,armeabi`, `abilist64=arm64-v8a` 显式写进 system `build.prop`, init 不再从 vendor 的空 `abilist32` 派生.
- **`ro.dalvik.vm.enable_uffd_gc=false`**, system 和 product 的 `build.prop` 都写 (底包的 `true` 在后加载的 product 里). Tango 不支持 userfaultfd, 32 位 ART 只能用 CC GC; 而 odrefresh 默认按 CMC 编 32 位启动镜像, 两边不一致 (V79 日志 `read barrier state mismatch`). 代价是 64 位 ART 也改用 CC.

## vendor 32 位自检

`abilist32` 一旦非空, 开机早期会同步执行 32 位 BoringSSL 自检:

| 服务 | 定义位置 | 时机 | 失败后果 |
| --- | --- | --- | --- |
| `boringssl_self_test32_vendor` | vendor `etc/init/boringssl_self_test.rc` | `early-init` | `reboot_on_failure`. 联想 vendor 没有 `/vendor/bin/boringssl_self_test32`, 必定失败并重启 |
| `boringssl_self_test32` | system `init.rc` | `init` | 不重启; `ro.zygote=zygote64` 时不触发 |
| `boringssl_self_test_apex32` | system `init.rc` | `apexd.status=ready` | 同上 |

`files/tango-boringssl32.rc` 把三个服务都换成同名的 64 位程序 (标签和域转换不变, 不用加策略). system 的两个用 `override` 兜底; vendor 的那个依靠 init 先到先得: `/system/etc/init` 比 `/vendor/etc/init` 先解析, vendor 后来的同名定义没有 `override`, 被丢弃. 替身不能用 `/system/bin/true`: 它是 toybox (`toolbox_exec`), init 没有到它的域转换, 服务起不来.

构建时 `check_vendor32.py` 扫描原厂 vendor 的全部 rc: 带 `reboot_on_failure` 或 `critical`, 程序是 32 位 ELF (或名字以 32 结尾但文件不存在), 又不在已接管名单里的服务, 会让构建停止.

## 开机保险

`files/tango-guard.sh` 在 `post-fs-data` 以 `exec_start` 运行 (herald 域, 早于 `zygote-start`), 默认 (`ENFORCE=0`) 只执行让 32 位能运行的必要步骤, 失败只记录日志:

1. 写 `0` 到 `/proc/sys/walt/panic_on_walt_bug`. 联想 `sched-walt.ko` 在任务带 `TIF_32BIT` 且目标核不在 32 位核掩码中时触发 `BUG()`; 本机没有 32 位核, `tango32` 转发 compat ioctl 时临时置位 `TIF_32BIT`, 任务一迁移就整机重启 (见[调研记录](https://github.com/CharlesGool/tango-porting-guide/blob/main/doc/research.md#真因-walt-32-位任务自检)).
2. `/dev/tango32` 不存在时再 `insmod` 一次.
3. 置 `tango.zygote32=1`, 运行 `files/tango-export.sh` 导出日志.

结果写到 `/metadata/tango_log/guard.txt`, 上一次的保留为 `guard.prev.txt`.

建 `/metadata/tango_log/guard_enforce` 或 `setprop persist.tango.guard_enforce 1` 后 (`ENFORCE=1`), 另外执行崩溃检测: 拷贝 `/sys/fs/pstore` 现场到 `pstore_<时间>/`; `fallback` 标记存在, 上次带 32 位开机没撑到开机完成后 120 秒 (`booting` 标记仍在), WALT 自检关不掉或模块没加载时, 用 resetprop 撤掉 32 位 ABI, 置 `tango.fallback=1`, 按纯 64 位开机. 标记文件第一行是写入它的版本号, 版本不同时丢弃. 默认关闭的原因: 32 位已在本机验证稳定, 检测会把开机 120 秒内的任何重启当成崩溃, 而 resetprop 修改 `ro.*` 属性会留下可被检测的痕迹.

`files/tango-stable.sh` 在开机完成 120 秒后删除 `booting` 标记并再导出一次日志. `tango-export.sh` 把 `/metadata/tango_log` 和当前 pstore 复制到 `/data/local/tmp/tango_log`, shell 可读, 用 `adb pull` 获取.

## heraldctl 命令

| 命令 | 作用 |
| --- | --- |
| `heraldctl tango status` | 模块, 32 位 ABI, 是否回退及原因 |
| `heraldctl tango retry` | 删除回退标记, 下次开机重新带 32 位 |
| `heraldctl tango off` | 写回退标记, 下次开机按纯 64 位. 默认 `ENFORCE=0` 时不生效, 见 [LOG 缺陷](https://github.com/CharlesGool/tb321fu-tango-patch/blob/main/doc/LOG.md#缺陷) |
| `heraldctl tango logs` | 导出日志到 `/data/local/tmp/tango_log` |
| `heraldctl tango zygote32 start\|stop` | 回退状态下手动起停 32 位 zygote, 用于隔离测试 |

## 改动清单

- `system/build.prop`: `ro.product.cpu.abilist`, `abilist32`, `abilist64`, `ro.dalvik.vm.enable_uffd_gc=false`; `product/etc/build.prop`: `ro.dalvik.vm.enable_uffd_gc=false`. 不改 `ro.zygote`.
- `system/etc/init/`: `tango-zygote32.rc`, `tango-boringssl32.rc`, `tango-guard.rc`.
- `system/etc/tango/`: `tango-guard.sh`, `tango-stable.sh`, `tango-export.sh`.
- herald 插件: `system/etc/herald_payload/plugins/tango.sh` (broker), `system/etc/heraldctl.d/tango.sh` (heraldctl).

## 输入

`STOCK_VENDOR_IMG`: 原厂 vendor 镜像, 只读挂载后扫描 rc.

## 依赖和适用范围

- 构建依赖 herald-core (`patch.conf` 的 `REQUIRES`). 功能上需要前 4 个部分都在, 否则 32 位 zygote 起不来, 被 init 反复重启; 因为去掉了 `onrestart restart zygote`, 不会拖垮系统.
- 底包**必须**有 `init.zygote64_32.rc` (用来核对 `zygote_secondary` 的命令行没变), `bin/app_process32`, `bin/boringssl_self_test64`; 原厂 vendor **必须**有 `bin/boringssl_self_test64`. 缺少时构建停止.
- 换 vendor 后扫出新的危险 32 位服务时, 照 `tango-boringssl32.rc` 加替身, 再把服务名加进 `part.sh` 中 `check_vendor32.py` 的已接管名单.
- odm 没有扫描 (联想 A15 底包的 odm 只有 `ueventd.rc`); 换底包时如果 odm 有 init rc, 需要人工检查.

## 验证

```bash
adb shell getprop sys.boot.reason.last       # 不是 reboot,boringssl-self-check-failed
adb shell getprop ro.zygote                  # zygote64
adb shell getprop ro.product.cpu.abilist     # arm64-v8a,armeabi-v7a,armeabi
adb shell getprop tango.zygote32             # 1
adb shell ps -A | grep zygote                # 64 位和 32 位 zygote 都在
adb shell cat /proc/sys/walt/panic_on_walt_bug   # 0
adb shell cat /metadata/tango_log/guard.txt
```
