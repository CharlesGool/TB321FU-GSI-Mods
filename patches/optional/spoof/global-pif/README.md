# spoof/global-pif — 全局指纹伪装

## 做什么

按 profile 把 build 身份(指纹、机型、版本等 13 个属性)全局 resetprop 成目标机型(比如 Pixel 7 panther),让 gms 里加固的 DroidGuard 进程用 native 读属性时也得到伪装值。**默认不伪装**,要用 `heraldctl spoof set <profile>` 打开,`heraldctl spoof off` 关掉。

## 原理

Play 判定在 `com.google.android.gms.unstable`(DroidGuard)里生成,它走 native `__system_property_get` 读 `ro.build.*`。只改 Java 的 `Build.*`(framework.jar)不行,Java/native 不一致会被抓;在加固进程里装钩子也不行(PLT hook 被 BTI/只读 libc 挡、私有属性区被 SELinux 拒,V28)。所以改成**全局**改属性源值:不在任何进程里装钩子,直接 resetprop,所有进程读到的都是伪装值。

- 时机必须在 `post-fs-data`(zygote 之前):`android.os.Build` 的静态字段在 zygote 加载 Build 类那一刻就从属性冻结了,挪晚了会失效。
- 只覆盖 proven 的 13 个身份属性并**并行**写(V30):属性列表太大(V29 近 70 个、串行)会把 PackageManager 建 packages.list 的临界窗口拖长,keystore 的 uid→包名解析抓到空快照,attestation 全路由回真实 System。
- 用 `exec_start`(同步阻塞)触发(V46):用异步 `start` 时 init 不等脚本跑完就走到 `zygote-start`,属性可能还没写完 zygote 就先起了——这才是 V37 要用"重启 zygote"补救的那场竞速的真因,重启 zygote 又会留下 selinuxfs sequence/policyload 不匹配的痕迹。
- profile 的 release 只要求非空(V42,允许 CANARY/beta):用户实测最初过认证的就是 panther_beta。
- 关闭伪装时,展示层的 security_patch 要纠正回真机值(V39):keymint 自带的特权 resetprop helper 每次开机把 security_patch 同步成认证层配置里的值,和这个开关无关,所以关着时事后纠正(认证层缓存的 patch 声明不受影响)。

## 改动清单

- `etc/herald_payload/herald-global-pif.sh`、`etc/init/init.herald-globalpif.rc`(一个 oneshot 服务 + `on post-fs-data exec_start`)。

## 依赖和顺序

`require_mod required/general/attestation-fix`:用核心的 herald 域、resetprop,引擎的 seed 和 broker 的 `spoof` 命令。不装它时核心仍可用,只是 `spoof set` 写的 profile 和标记没人去应用。

## 换底包注意

脚本只依赖 `resetprop` 和 profile 文件,和底包无关。要注意 init 的 trigger 顺序:`post-fs-data` 到 `zygote-start` 之间必须还在,换了 Android 版本后核对 `hw/init.rc`。

## 踩过的坑

见上面各条(V28 / V30 / V39 / V42 / V46)。

## 验证

```bash
adb shell heraldctl spoof set pixel7.json && adb reboot
adb shell getprop ro.build.fingerprint     # 伪装值
adb shell heraldctl spoof off && adb reboot
adb shell getprop ro.build.fingerprint     # 回到原厂 TB321FU
```

## V76:/system/build.prop 跟着伪装
伪装开着的那次开机,`herald-global-pif.sh` 在写完属性后把 `/system/build.prop` 里这 15 个键换成 profile 的值,存成 `/dev/herald_build.prop`(标签 system_file),`mount -o bind` 盖到 `/system/build.prop` 上。目的:检测工具(Hunter 等)比"运行时属性 vs build.prop 文件",V75 报了 6 条不一致。
- fail-soft:文件缺失、含反斜杠、行数对不上、指纹行没换成功、chcon 或 mount 失败,都不盖,回到 V75 的状态。
- 关伪装后重启,不走这段,`/system/build.prop` 就是原文件。伪装值改了要重启才会同步到文件(属性本身是运行时改的)。
- 代价:`/proc/self/mountinfo` 里会多一条盖在 `/system/build.prop` 上的 bind 挂载(源是 tmpfs 的 `/herald_build.prop`),检测工具若查挂载表可能当成新特征。**没上真机**,看日志 `heraldctl diag` 或 `logcat -s herald-global-pif`,关键词"build.prop 同步"。
- 只改了 `/system/build.prop`;`ro.system.*`、vendor/product 分区的 build.prop 不动(它们的值本来就没被运行时改过)。

### V77:换掉 tmpfs、只读重挂载
V76 真机:Hunter 的 6 条消失了,但另一款检测软件因为 bind 挂载报了 2 条强风险:`SYSTEM_PARTITION_WRITABLE`(挂载选项和 tmpfs 超级块都是 rw)、`ACTIVE_STACKED_FS_OVER_SYSTEM fs=tmpfs`。改成:替换文件放 `/data/system/build.prop`(真实文件系统,挂载表 root 列显示 `/system/build.prop`),bind 后 `mount -o remount,bind,ro`。关伪装那次开机会删掉 `/data/system/build.prop`。没上真机:`/data` 的超级块仍是 rw、文件系统类型是 f2fs/ext4 而不是 erofs,检测软件会不会换个说法再报,要看结果。

### V81:停用 build.prop 同步
V80 真机:只读重挂载没生效(挂载表仍是 rw),而且换成 `/data` 后被报 `ACTIVE_DATA_BACKED_SYSTEM_MOUNT`。只要用 bind 盖文件,挂载表就能看到来源,所以停用,回到 V75 的状态(Hunter 会报属性和 build.prop 不一致)。根本解法是不改全局属性、改成按 App 伪装,V82 起做。

### V82:恢复 build.prop 同步
用户选择:宁可挂载检测报 `ACTIVE_DATA_BACKED_SYSTEM_MOUNT`,也不要 Hunter 报属性和 build.prop 不一致。恢复 V80 的做法(`/data/system/build.prop` bind 到 `/system/build.prop`)。只读重挂载在 V80 真机上没生效,现在换四种 `mount -o` 写法逐个试,每次读 `/proc/self/mountinfo` 核对,日志里记下哪种成功(`global-pif.log` 的"build.prop 同步"行)。
