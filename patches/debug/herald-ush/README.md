# herald-ush — 装上即用的 root 命令 `ush`

## 做什么

给 herald broker 加一个 `ush` 命令,以 root(broker 的 herald 域)`sh -c` 跑一整条命令,并装一个无特权前端 `/system/bin/ush`。用起来像 `su`,但**不叫 `su`**:

```
adb shell ush <命令>          以 root 跑整条命令(支持管道、重定向、&&)
adb shell ush -c "<命令>"     su 风格
adb shell ush                 不带参数:交互式 root shell(逐条执行,exit/quit 退出)
```

退出码就是所跑命令的退出码,输出原样打印。

和 [herald-readonly-shell](../herald-readonly-shell/)(`heraldctl rexec`,只读白名单)的区别:**没有白名单、没有敏感路径限制,也不需要先开启**——打了这个补丁,`ush` 就直接能用。

## 为什么不叫 su / 为什么不易被检测

常规的 root 检测扫的是:PATH 上有没有叫 `su` 的二进制、有没有带 setuid 位的可执行文件、Magisk 的痕迹。这个补丁:

- 命令叫 `ush`,**不叫 `su`**,也不往 `/system/bin`、`/system/xbin`、`/sbin` 放任何叫 `su` 的东西;
- `/system/bin/ush` 是**普通无特权脚本,没有 setuid 位**——root 不是靠它自己提权拿到的,而是把命令交给早已常驻的 herald broker(由 init 在 `u:r:herald` 域拉起)执行;
- 没有引入新的 setuid 二进制、没有改 `ro.debuggable`、没有动 SELinux 策略。

所以查 `su` / 查 setuid 的检测扫不到。注意这不是"系统里完全没有 root 通道":herald broker 本身是一个 root 服务,专门查 herald 的检测仍可能发现它——它防的是针对 `su` 的常规检测,不是万能隐身。

## 怎么工作

`/system/bin/ush`(uid 2000,无特权)把 `ush <命令>` 写进命令通道 `/data/local/tmp/herald/req.<id>`,broker 的 `ush` 插件以 root `sh -c` 跑它,回包从 `resp.<id>` 读回(和 `heraldctl` 同一套通道,见 [herald-core](../../required/general/herald-core/))。为防随手滥用(不是安全边界):

- 只接受命令行通道(`adb shell`,uid 2000,需 USB 调试授权),配对的前端 App 一律拒绝;
- 每条命令原文和退出码都写 `heraldctl log`;
- 命令列进 `HERALDP_ASYNC` 后台执行,慢命令不阻塞 broker 主循环;单条 600 秒超时,输出最多 256KB。
- 能 `adb shell` 的人本来就能改 broker,所以这不防恶意的设备所有者;它只防针对 `su` 的检测。
- **只放调试版,默认不打**(`WITH=debug` 选上)。

带管道/重定向时,电脑上要把整条命令用引号包住,否则会被设备的 shell 先拆开:

```
adb shell "ush 'ls -l /data/misc/keystore | head'"
adb shell "ush 'resetprop -n ro.product.manufacturer Lenovo'"
```

交互式 root shell 里每条命令是独立的 `sh -c`,**`cd`、环境变量不跨条保留**,`vi`/`top` 这类需要真 tty 的程序也不正常(走的是请求/回包,不是伪终端)。要在某个目录下跑就写进一条:`ush 'cd /data && ls'`。

## 输入

无。需要 `required/general/herald-core` 在前面(broker 和命令通道)。

## 验证

DP11(A17 QPR3)真机验证通过(在 user-v1.2-cust-bebug 上):`adb shell ush id` 得 `uid=0(root) … context=u:r:herald:s0`;`-c`、分号/管道(整条包引号时)、直接传参都以 root 跑;`ls /data/data`、`/data/misc` 等只有 root 能读的路径读得了;`/system/bin/ush` 是 `-rwxr-xr-x`(**无 setuid 位**),`which su` 为空、`/system/bin/su` 不存在。herald 域在真机上确为 permissive,命令照跑。

构建侧也在电脑上用假环境核对过:插件命令名/通道拒绝 App、前端把 `ush <命令>` 正确拼成请求、`ok ush rc=` 协议解析和退出码透传、`-c` 与直接传参、交互式读到 EOF 退出。
