# tango/zygote32

## 做什么

声明系统支持 32 位 ABI,并起一个 32 位 zygote(`zygote_secondary`),32 位 APK 才能安装和启动。顺带:接管"一声明 32 位 ABI 就会在开机早期被触发"的 vendor 32 位自检、
把 ART 的 GC 统一成 CC、开机保险(Tango 出问题自动回退纯 64 位)和崩溃现场导出。

**2026-10-31 起照小米 14 Ultra 的做法重写**(对照见工程 `doc/tango-research.md`):

- **不改 `ro.zygote`**(保持 vendor 的 `zygote64`)。自带 `files/tango-zygote32.rc`:服务 **`tango_zygote32`**(V881 真机:叫 `zygote_secondary` 会被原版 init.rc `on zygote-start` 里无条件的 `start zygote_secondary` 拉起,`disabled` 挡不住;回退时它反复 abort 触发 init 的 updatable_crashing 整机重启),定义抄原版 `zygote_secondary`,去掉 `onrestart restart zygote`、加 `disabled`,
  `on zygote-start && property:tango.zygote32=1` 才启动。好处:init 不 import `init.zygote64_32.rc` / `init.boringssl.zygote64_32.rc`,system 的两个 32 位自检不触发,也不用改原版 rc;
  V77 那种"写了 ro.zygote 却被 vendor 盖回去"的坑不存在了。socket 名仍是 `zygote_secondary`,system_server 的 `ZygoteProcess` 按名字连。
- `ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi`、`abilist32=armeabi-v7a,armeabi`、`abilist64=arm64-v8a` 显式写进 system `build.prop`(init 不再从 vendor 的空 `abilist32` 派生)。
- **`ro.dalvik.vm.enable_uffd_gc=false`**:Tango 不支持 userfaultfd,32 位 ART 只能走 CC GC;底包是 `true`,odrefresh 按 CMC 编 32 位启动镜像,V79 真机日志 `read barrier state mismatch`,32 位进程没有启动镜像可用。
  小米 product/build.prop 同样设 `false`。代价:64 位也用 CC;改动后第一次开机 odrefresh 重编一次 /data 下的启动镜像。
- vendor 的 32 位 BoringSSL 自检仍要接管(`files/tango-boringssl32.rc`):联想 vendor 的 rc 只看 `abilist32`,不看 `ro.zygote`(小米 vendor 是 `import ...${ro.zygote}.rc`,所以小米不用接管)。
- 开机保险 `files/tango-guard.sh`(post-fs-data,exec_start,herald 域):模块不在、或上次带 32 位开机没撑到稳定 → resetprop 撤掉 32 位 ABI、置 `tango.fallback=1`、不放行;否则置 `tango.zygote32=1`。
  两种结果都会跑 `files/tango-export.sh`,把 `/metadata/tango_log`(guard.txt、pstore_* 崩溃现场、翻译器日志)和当前 `/sys/fs/pstore` 复制到 **`/data/local/tmp/tango_log`**(shell 可读),`adb pull` 直接取。
- 标记文件(booting / fallback)第一行写版本号,刷新版本后旧标记自动丢弃;`guard.txt` 轮换到 `guard.prev.txt`,逐行 `sync`。
- `heraldctl tango status|retry|off|logs|zygote32 start|zygote32 stop`。`zygote32 start` 在回退状态下临时给上 abilist32 并起 `tango_zygote32`,用来隔离"32 位 zygote 跑起来"这一步。

### 32 位自检(`files/tango-boringssl32.rc`)

`abilist32` 一非空,开机早期会**同步**跑三个 32 位 BoringSSL 自检:

| 服务 | 定义在 | 时机 | 程序 | 失败会怎样 |
|---|---|---|---|---|
| `boringssl_self_test32_vendor` | vendor `etc/init/boringssl_self_test.rc` | `early-init` | `/vendor/bin/boringssl_self_test32` | `reboot_on_failure reboot,boringssl-self-check-failed`。**联想 vendor 没有这个文件**,必定失败 → 重启 |
| `boringssl_self_test32` | system `init.rc` | `init` | `/system/bin/boringssl_self_test32`(要 Tango 翻译) | A15 里不重启;但 `exec_start` 等它退出,翻译器卡住 init 就卡住 |
| `boringssl_self_test_apex32` | system `init.rc` | `apexd.status=ready` | conscrypt APEX 的 32 位版 | 同上 |

现在 `ro.zygote` 保持 `zygote64`,system 的两个根本不触发;vendor 那个必须接管。三个都换成同名的 64 位程序(标签和域转换都不变,不用加策略)。system 的两个用 `override` 顶掉 init.rc 里的定义(兜底);
vendor 的那个靠 init 的"先到先得":`/system/etc/init` 比 `/vendor/etc/init` 先解析,这里先定义,vendor 后来的同名定义没带 `override`,被丢弃(日志里一行 `ignored duplicate definition`)。

构建时 `check_vendor32.py` 会扫原厂 vendor 的全部 rc:凡是带 `reboot_on_failure` / `critical`、程序是 32 位 ELF(或名字以 32 结尾但文件不存在)、又不在已接管名单里的服务,构建直接停。换 vendor 底包后多出来的同类服务会在这里被拦下,而不是刷上去才发现开不了机。

### zygote_secondary 不再连带重启 zygote

原版 `init.zygote64_32.rc` 里 `zygote_secondary` 有 `onrestart restart zygote`:32 位 zygote 一死,64 位 zygote 和 system_server 跟着重启。Tango 有问题时 32 位 zygote 会反复崩,整机就卡在开机动画。
自带的服务定义没有这一行:32 位 zygote 坏了只影响 32 位 app,系统照常进;system_server 的 `ZygoteProcess` 下次要起 32 位进程时会自己重连 secondary。

## 改动清单

- `system/build.prop`:`ro.product.cpu.abilist`、`ro.product.cpu.abilist32`、`ro.product.cpu.abilist64`、`ro.dalvik.vm.enable_uffd_gc=false`;`product/etc/build.prop` 的 `ro.dalvik.vm.enable_uffd_gc` 也改 false(底包的 true 在这里,后加载)。**不碰 `ro.zygote`**。
- 新增 `system/etc/init/tango-zygote32.rc`(32 位 zygote 服务)、`tango-boringssl32.rc`(自检替身)、`tango-guard.rc`(保险)。
- 新增 `system/etc/tango/tango-guard.sh`、`tango-stable.sh`、`tango-export.sh`;broker 插件 `herald_payload/plugins/tango.sh`;heraldctl 插件 `heraldctl.d/tango.sh`。
- 原版 `init.zygote64_32.rc` 不再改。

## 输入

`STOCK_VENDOR_IMG`(原厂 vendor 镜像,只读挂载来扫 rc,device.conf 本来就有)。

## 依赖和顺序

构建上无依赖。**功能上必须先有 core + sepolicy + kernel-module + vendor-lib32**,否则 `zygote_secondary` 起不来、被 init 反复重启(日志刷屏、耗电;因为删了 `onrestart restart zygote`,不会拖垮系统)。

## 适用范围和换底包注意

- 需要底包有 `init.zygote64_32.rc`(只用来核对 `zygote_secondary` 的命令行没变)、`bin/app_process32`、`bin/boringssl_self_test64`,否则构建停。
- 换 vendor:原厂 vendor 要有 `bin/boringssl_self_test64`;扫出新的危险 32 位服务时构建停,照 `tango-boringssl32.rc` 的写法加一条替身,再把名字加进 `apply.sh` 里 `check_vendor32.py` 的已接管名单。
- odm(联想 A15 底包的 odm 只有 `ueventd.rc`)没扫;换底包时如果 odm 里有 init rc,手动看一眼。
- `ro.zygote` 在 vendor 的 `build.prop` 也有一份(`zygote64`)。init 按 system → vendor → odm → product 加载,**后加载的 ro.* 覆盖前面的**(V77 真机实测:只写 system 时运行时是 `zygote64`)。现在干脆不改它。

## 踩过的坑

- **V68 卡第一屏开机循环**,重启原因 `reboot,boringssl-self-check-failed`。当时以为是 system 的 32 位自检跑在 `tango32.ko` 加载之前,只改了 system 的两个自检和 insmod 的时机。其实 A15 的 system 自检**没有** `reboot_on_failure`,能报这个重启原因的只有 vendor 的 `boringssl_self_test32_vendor`,它的程序在联想 vendor 里根本不存在,跟 Tango 好不好使无关。现在三个都接管,并在构建时扫 vendor。
- 替身不能用 `/system/bin/true`:它是 toybox(`toolbox_exec`),init 到它没有域转换,`Service::Start` 会报 "has incorrect label or no domain transition" 直接起不来。所以换成同名的 64 位程序。
- **V883 真机通过**。V882 整机重启的真因:联想 `sched-walt.ko` 的 32 位任务自检(`WALT-BUG selecting non 32 bit cpu` → `BUG()`),保险脚本放行前写 `/proc/sys/walt/panic_on_walt_bug=0`(默认 1162010139 = 魔数 0x4544de00 | 0x1b,bit1 是 BUG、bit4 是打印;魔数对不上整套跳过)。写不进去就不放行。详见工程 `doc/tango-research.md` 4d 节。
- V881 真机:原版 init.rc 的 `on zygote-start` 无条件 `start zygote_secondary`,`disabled` 挡不住显式 start,回退时它被拉起、因 abilist32 为空反复 abort,触发 init 的 `updatable_crashing` 整机重启 → 服务改名 `tango_zygote32`。`enable_uffd_gc` 的 true 在 product/etc/build.prop,system 和 product 都要写。

## 验证

```bash
adb shell getprop sys.boot.reason.last       # 不应再是 reboot,boringssl-self-check-failed
adb shell getprop ro.zygote                  # zygote64_32
adb shell getprop ro.product.cpu.abilist     # arm64-v8a,armeabi-v7a,armeabi
adb shell ps -A | grep zygote                # zygote64 + zygote,PID 不变
adb shell "dmesg | grep -i boringssl"        # 三个自检都跑的 64 位版,没有失败
adb shell "logcat -d -b all | grep -i 'boringssl_self_test32_vendor'"   # 应有一行 ignored duplicate definition
```

## V79:开机保险(tango-guard)
V78 真机:`ro.zygote` 修好了,但 `tango32.ko` 没加载上,32 位 zygote 经翻译器一启动就 SIGILL(32 位库 CFI 检查失败),system_server 等它,卡第二屏。
现在 `post-fs-data`(exec_start,先于 zygote-start)跑 `/system/etc/tango/tango-guard.sh`(herald 域,要 herald-core 的 resetprop):
- `/dev/tango32` 不在 → 再 insmod 一次,insmod 报错、`/proc/modules`、相关内核日志写到 `/metadata/tango_log/guard.txt`(shell 可读,卡开机也能取)。
- 还是不在 → resetprop 把 `ro.product.cpu.abilist` 改成 `arm64-v8a`、删掉 `ro.product.cpu.abilist32`,置 `tango.fallback=1`,在 zygote-start 停掉 `zygote_secondary`。整机按纯 64 位开机,32 位 APK 不可用。
- 模块在 → 什么都不改。
已排除:tango32.ko 用到的 31 个内核符号都在 GKI 的 KMI 符号列表里,没有用到受保护导出(`abi_gki_protected_exports_aarch64`),所以"没签名"不是加载失败的原因。真正原因等 guard.txt。
