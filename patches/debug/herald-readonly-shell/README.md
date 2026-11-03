# herald-readonly-shell — 以 root 跑只读查看命令

## 做什么

给 OMK 控制后端加 `rexec` 命令,用 root 身份执行一批**只读**的查看类程序,用来分析系统(读 `/data` 下普通用户读不到的文件、`dumpsys`、`ps`/`lsof` 看全部进程、`logcat -d -b all` 等)。

```
heraldctl rexec on [分钟]      打开,默认 30 分钟,最多 120,到点自动关
heraldctl rexec status | off
heraldctl rexec <命令> [参数…]  跑命令,输出原样打印,退出码就是命令的退出码
```

## 为什么是白名单,不是"root shell + 黑名单"

黑名单拦不住 shell:`sh -c`、`$()`、`base64 -d | sh`、`python`、重定向到系统路径,换个写法就绕过去,只是防手滑。所以这里**不经 shell**,只放行一批只读程序,个别程序再限制参数。

## 限制

- **通道**:只接受 `adb shell heraldctl`(命令行通道)。配对的前端 App 调用会被拒绝,不能给 App 开 root。
- **开关**:默认关,`rexec on` 打开后到点自动关;每条命令和每次拒绝都写 `heraldctl log`。
- **不经 shell**:命令行里有 `; | & < > $ ` ( ) { } \ ' "` 直接拒绝;参数按空格切,不支持带空格的参数。管道/重定向在电脑上做(`adb shell heraldctl rexec ... > out.txt`)。
- **白名单程序**:`cat ls stat readlink realpath file wc head tail cut md5sum sha1sum sha256sum od hexdump strings lsattr df du id uname uptime whoami ps lsof lsmod pidof getenforce getprop ss netstat which nproc free vmstat grep find sort dmesg logcat dumpsys date mount wm service settings pm cmd ip`。
  - `find` 不允许 `-exec -execdir -ok -okdir -delete -fprint*  -fls`;`sort` 不允许 `-o`;`dmesg` 不允许清缓冲和改级别;`logcat` 必须带 `-d`(或 `-g/-S/-L`),不允许清缓冲/写文件;`dumpsys` 不允许 `set unplug reset enable disable override force …` 这类改状态的参数;`date` 只允许 `+格式`;`mount` 只能无参数;`wm` 只能 `size`/`density`;`service` 只能 `list`/`check`;`settings` 只能 `get`/`list`;`pm` 只能 `list/path/dump/resolve-activity`;`cmd` 只能 `overlay list/dump/lookup`、`package list/path/dump/resolve-activity`、`wifi status/get-country-code/list-networks`;`ip` 只能 `addr/route/link/neigh/rule` 且不能带 `add del set flush …`。
- **敏感路径**(路径先 `readlink -f` 解符号链接再比,出现在参数里的任何位置都拒绝):`/data/misc/keystore`(含 OMK 数据、keybox)、`/data/adb`、`/data/local/tmp/herald`(命令通道)、`/system/etc/herald_payload`、`/data/misc/apexdata/com.android.wifi`、`/data/misc/wifi`(Wi-Fi 密码)、`/data/misc/vold`、`/metadata/vold`、`/data/misc/bluedroid`、`/data/misc/user`、`/data/misc_ce`、`/data/misc_de`、`/data/system/gatekeeper`、`/data/system/locksettings`、`/data/system_ce`、`/data/system_de`(账号令牌)、`/dev/block`、`/dev/mem`、`/dev/kmem`、`/proc/kcore`、`/proc/*/mem`,以及叫 `herald_token`/`herald_req`/`herald_resp` 的文件。
- **递归类命令**(`find`、`du`、`grep -r`、`ls -R`)不允许从敏感目录的上级开始:`find / ...`、`grep -r foo /data` 会被拒绝。
- 单条命令 30 秒超时,输出最多 256KB;命令运行期间 broker 不处理别的请求。

## 不能防的

- 这是**防误操作加限制范围**,不是对恶意设备所有者的安全边界:能 `adb shell` 的人本来就能改 broker。
- 白名单程序本身的输出可能含隐私(`logcat`、`dumpsys`、`ps`)。
- `/data/data/<包名>` 下 App 的私有数据没有列入敏感路径(分析用),别拿这条命令的输出随手发给别人。

## 输入

无。需要 `herald-core` 在前面。
