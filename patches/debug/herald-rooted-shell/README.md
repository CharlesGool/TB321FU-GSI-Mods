# herald-rooted-shell — 经 herald 以 root 跑任意命令

## 做什么

给 herald broker 加 `rsh` 命令:用 root 身份(broker 的 herald 域)`sh -c` 跑一整条命令,支持管道、重定向、`&&`。和 [herald-readonly-shell](../herald-readonly-shell/) 的区别是**没有白名单也没有敏感路径限制**,调试时想读/改什么都行。有了它就不用靠 [debug/adb](../adb/) 的 `ro.debuggable=1`/`ro.secure=0` 去拿 root(那样 adbd 虽然是 uid 0,SELinux 的 shell 域仍受限)。

```
heraldctl rsh on [分钟]     打开,默认 15,最多 60,到点自动关
heraldctl rsh off | status
heraldctl rsh <命令>        跑命令,输出原样打印,退出码就是命令的退出码
```

电脑上带管道/重定向要把整条命令用引号包住,否则会被设备的 shell 先拆开:

```
adb shell "heraldctl rsh 'ls -l /data/misc/keystore | head'"
adb shell "heraldctl rsh 'resetprop -n ro.product.manufacturer Lenovo'"
```

## 限制(防误用,不是安全边界)

- 只接受 `adb shell heraldctl`(命令行通道),配对的前端 App 一律拒绝。
- 默认关,`rsh on` 打开后到点自动关;每条命令原文和退出码都写 `heraldctl log`。
- 单条 60 秒超时,输出最多 256KB;命令运行期间 broker 不处理别的请求。
- 能 `adb shell` 的人本来就能改 broker,所以这不防恶意设备所有者;它和 readonly-shell 的区别只是**去掉了白名单**。
- **只放在调试版里**,默认不打。

## 注意

- 命令跑在 herald 域。这个域在已看到的日志里是宽容的(`permissive=1`),但 SELinux 的行为以真机为准。
- 没上真机验证;在电脑上用假环境测过开关、拒绝 App 通道、带管道的命令、退出码。

## 输入

无。需要 `herald-core` 在前面。
