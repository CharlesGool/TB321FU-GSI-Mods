# toolkit/vendor-bind:开机把补丁文件 bind 到 /vendor

这是基础设施库,**不是模块**。没有 `MODS` 里的条目,谁都不需要"先启用"它。用它的模块在 `apply.sh` 里 `source "$TOOLKIT/lib/vendorbind.sh"`,
调用 `vendor_bind_add`;第一次调用时它自动把开机脚本和 rc 装进树里(树里已经有一模一样的就跳过),之后每次调用只追加自己的描述符。
所以用它的模块之间互不依赖,单独启用、任意组合、任意顺序都行。目前的使用者:`bluetooth/a2dp-offload-policy`、`bluetooth/sco-call-fix`。

## 做什么

GSI 只换 system,vendor 是原厂的,改不了。有些修复要改 vendor 里的文件(音频策略、HAL 库)。办法是把改好的文件放进 system,
开机时 `mount -o bind` 盖到 /vendor 的原路径上。盖之前必须确认 vendor 里的原文件**就是打补丁时用的那份**(比 sha256)——
vendor 升级后文件变了,旧补丁盖上去会出事,所以对不上就不盖。

## 机制

- `/system/etc/vendor-bind/*.bind`:描述符,每个补丁一个,三行 `key=value`:
  ```
  target=/vendor/lib64/hw/xxx.so          # 要盖住的 vendor 文件
  patch=/system/etc/vendor-bind/xxx.file  # 补丁文件
  sha256=<64 位十六进制>                     # vendor 里 target 的原文件应有的 sha256
  ```
  `#` 开头的行和空行忽略。`target` 必须在 /vendor/ 下,`patch` 必须在 /system/ 下。
- `/system/bin/vendor-bind.sh`(源:`vendor-bind.sh.in`):逐个读描述符。顺序:① `ro.product.vendor.device` 不等于构建时的 `$DEVICE` 就直接退出;
  ② 补丁文件或目标文件不存在 → 跳过;③ 目标文件的 sha256 和描述符里的不一样 → 跳过;④ 否则 `mount -o bind`。
  每一步结果写 dmesg,前缀 `vendor-bind:`(`ok` / `skip` / `FAIL`)。一个出问题不影响其它的。
- `/system/etc/init/vendor-bind.rc`(源:`vendor-bind.rc`):`on post-fs` 里 `exec - root -- /system/bin/vendor-bind.sh`。post-fs 在音频等 HAL 启动之前。
- 脚本的 SELinux 标签是 `update_engine_exec`:init 的 `exec` 要求可执行文件有到别的域的 domain transition,
  `system_file` 没有;plat 策略里有 `typetransition init update_engine_exec process update_engine`。V1 起就这么用。
- 脚本只用 POSIX sh 语法(Android 的 sh 是 mksh),`getprop`、`sha256sum`、`cut`、`mount` 都是系统自带的。

## 怎么用(写一个用它的模块)

```bash
source "$TOOLKIT/lib/vendorbind.sh"

vendor_stock_get lib64/hw/foo.so "$WORK/foo.stock.so"     # 从原厂 vendor 现取原文件
...打补丁,得到 $WORK/foo.so ...
vendor_bind_add /vendor/lib64/hw/foo.so "$WORK/foo.so" \
    "$(sha256sum "$WORK/foo.stock.so" | cut -d' ' -f1)" my-foo-patch u:object_r:vendor_file:s0
```

`vendor_bind_add <目标 vendor 路径> <补丁文件> <原文件sha256> <名字> [补丁文件标签]`:
首次调用装脚本和 rc、建 `etc/vendor-bind/`;然后把补丁文件放进 `etc/vendor-bind/<名字>.file`,写 `etc/vendor-bind/<名字>.bind`。
名字全局唯一,同一个目标文件不能被两个补丁登记(会 die)。树里已有但和这里生成的不一样的 `vendor-bind.sh` 也会 die,不覆盖。

- **补丁文件的标签要和被盖的 vendor 文件一致**(bind 后进程看到的是补丁文件自己的标签):.so 用 `vendor_file`(默认),音频策略 xml 用 `vendor_configs_file`。
- **原文件 sha256 必须是"打补丁用的那份原文件"现算的,不是补丁版的,也不能写死**(见"踩过的坑")。
- `vendor_stock_get <vendor 内相对路径> <输出文件>` 从 `STOCK_VENDOR_IMG` 现取原文件,文件不在就 die。

## 输入(device.conf)

| 变量 | 说明 |
|---|---|
| `DEVICE` | `ro.product.vendor.device` 的值,构建时写进脚本做设备守护,如 TB321FU |
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像(`vendor_stock_get` 用) |
| `VENDOR_BIND_EXEC_LABEL` | 可选,脚本的标签,默认 `u:object_r:update_engine_exec:s0` |
| `VENDOR_BIND_DEFAULT_LABEL` | 可选,`vendor_bind_add` 没传标签时补丁文件用的,默认 `u:object_r:vendor_file:s0` |

## 镜像里的改动

首次调用 `vendor_bind_add` 时新增:`etc/vendor-bind/`(目录)、`bin/vendor-bind.sh`(0755 root:shell)、`etc/init/vendor-bind.rc`。每个补丁再加 `<名字>.file` 和 `<名字>.bind`。
没有任何模块调用它时,镜像里什么都不会多。

## 适用范围和换底包注意

- 换 GSI:要求 system 里有 `etc/init`、`bin`。
- 换 vendor(原厂固件):不用改这里。使用它的模块构建时从新 vendor 现取原文件、现算 sha256,描述符自动跟着换;补丁本身打不上是那个模块 die。
- 刷了新 vendor 但没重新构建 system:描述符里的 sha256 和 vendor 对不上,全部跳过,系统回到原厂行为(安全失败)。

## 踩过的坑

- **V66:bind 脚本核对的是旧固件的 sha256,A15 设备上 SCO 补丁根本没生效。**
  V66 的 `tb321fu-vendor-fixes.sh` 里 audio.primary 的 `AHAL_STOCK_SHA256` 是 ZUI 17.5.10.170 的 `f468566…`,
  而 A15 设备(ZUI 17.0.12.044)vendor 里真实的是 `d8fcef36…`,两个版本的库只差 20 字节(build-id 和版本标记),
  补丁偏移相同,所以补丁"能打"却因为 sha 对不上被脚本跳过——`dmesg` 里只有一行 skip,功能上就是蓝牙通话照旧没声音。
  上一轮重整 A15 时发现并修掉。现在 sha256 一律在构建时从取出的原厂文件现算(`vendor_bind_add` 的第三个参数),
  模板里没有任何写死的 sha,构建用哪份原文件、开机就核对哪份。
- 排查"补丁没生效"先看 `dmesg | grep vendor-bind`:`skip ... sha256 of X is A, not the stock file ... (B)` 里 A 是设备上实际的值,B 是构建时的。
- **Enforcing 下 bind 不上(user-v1.1 的蓝牙没声音就是这个)。** 脚本以 update_engine 域运行,但 AOSP 策略里**没有任何域**能对 `vendor_file` / `vendor_configs_file`
  的文件做 `mounton`,update_engine 也不能读 `vendor_file` 标签的文件(`sha256sum` 目标 .so 读不出来、`[ -f ]` 补丁 .so 也 getattr 不了)。
  老的 tb321fu.rc 那套能工作,是因为 Mystic 底包 post-fs 阶段还是 Permissive;`selinux/fix` 让内核从头 Enforcing 之后,
  两个蓝牙补丁一个都没盖上,A2DP 又回到走高通 offload(没声音),通话回到被 AHAL 拦住。
  现在 `vendor-bind.cil` 给 update_engine 补了最小权限(`vendor_file` 的 getattr/read/open/mounton,`vendor_configs_file` 的 mounton),
  `_vendor_bind_install` 里 `cil_append` 追加到 plat_sepolicy.cil(构建收尾时清 sha256 强制开机重编)。
  用 secilc 把镜像里的 plat + 原厂 vendor + system_ext + product 策略编出来、`sesearch` 逐项核对过:补之前 5 项被拒,补之后脚本要的访问全部放行。
- 如果真机上 dmesg 里完全没有 `vendor-bind:` 行,查 `ro.product.vendor.device` 守护和 `dmesg | grep avc`。`FAIL` 行或 `sha256 of ... is , not the stock file`(空值)都是 SELinux 拒绝的特征。

## 验证

- 刷机后 `dmesg | grep vendor-bind`:每个补丁一行 `ok <名字>: <目标>`。
- 没有真机时的行为测试办法:把脚本里的 `DESC_DIR / VENDOR_ROOT / SYSTEM_ROOT / KMSG` 四个变量用 sed 指到临时目录,
  PATH 里放假的 `getprop` / `mount`(busybox sh 会优先用自带的 mount,要把假 mount 注入成函数),用 dash 和 busybox sh 跑。
  覆盖过的场景:sha 对得上 bind、sha 对不上跳过、目标缺失跳过、设备守护不匹配整体退出、多个描述符互不影响、
  坏描述符(目标/补丁路径不对、缺 sha、空文件)跳过、mount 失败写 FAIL、无描述符空操作。
