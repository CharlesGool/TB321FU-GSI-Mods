# herald-apps:内置功能 App 的专用通道

## 思路

- 每个功能做成一个独立的小 App,装在系统分区(`/system/system_ext/app/`),**没有桌面图标**,入口注入到设置里对应的页面(`com.android.settings.action.IA_SETTINGS`)。
- App 只管界面;读写都经 herald 的插件命令完成。
- **不用配对**:装在系统分区本身就是授权。每个 App 只能跑自己白名单里的命令,用户在普通版里接触不到 herald 的其他能力(heraldctl / ush 只在 bebug 分支)。

## 登记一个 App

功能 App 的模块放两样东西:
1. APK → `system_ext/app/<名字>/<名字>.apk`;
2. 白名单 → `/system/etc/herald_payload/apps/<包名>.allow`:每行一个 ERE,请求必须**整行完全匹配**其中一条(`#` 开头和空行忽略)。

可选:插件里定义 `heraldapp_post_<包名里的 . 换成 _>()`(`$1` = 请求整行),输出追加到回包,用来补字段。

## 协议(每个 App 自己的 `files/` 目录,只服务 user 0)

| 步骤 | 谁 | 做什么 |
|---|---|---|
| 1 | App | 删旧的 `herald_resp`,写 `herald_req.tmp`(一行命令)再 rename 成 `herald_req` |
| 2 | herald | ≤0.4 秒内取走(读完即删) |
| 3 | herald | 鉴权 + 白名单,执行 `heraldp_cmd_<命令>` |
| 4 | herald | 回包写 `herald_resp.tmp` 再 rename 成 `herald_resp`(第一行 `ok …` / `err <原因>`,后面 `key=value`) |

App 等 2.5 秒请求没被取走就认为后端不在。

## 鉴权

- 包装在系统分区:`pm path` 在 `/system/…`、`/system_ext/…`、`/product/…` 下且只有一行;被 `/data/app` 的更新盖住就拒绝。
- `pm` 报的 uid = 数据目录属主 = `files/` 属主 = 请求文件属主。鉴权结果在 `/data/system/packages.list` 没变(没装、卸、更新任何包)期间一直有效。
- 请求文件必须是 App 自己的普通文件(不是符号链接 / FIFO);只读前 200 字节,限时 2 秒。
- 被拒的请求只删除、不回包(不在白名单的回 `err not allowed`)。

## 回包的写法(安全 + SELinux)

在 App 目录里 `set -C`(O_EXCL)新建 0600 → `chown -h` 成 App 的 uid → `chcon -h` 成 `files/` 的上下文 → rename。
- `-h`:App 中途把文件换成符号链接,也只改到链接本身。
- `chcon` 必须做:herald 新建的文件只有 `s0`,App 的数据文件带它自己的 MLS 类别(`s0:cXXX,…`),AOSP 的 mls 规则对 `app_data_file` 的 open/unlink 要求级别相等,不改 App 打不开也删不掉。

## 运行方式

`HERALDP_START` 起一个独立子进程轮询各登记 App 的 `files/`:装了就每 0.4 秒看一次,都没装就 5 秒;等待用 `read -t` 读一个空 FIFO,不 fork sleep。
不占 broker 主循环;`herald_sys` 的临时文件放自己的 `/data/local/tmp/herald/.work-apps`(root 0700)。

## 测试

`HERALD_APPS_DIR` / `HERALD_APPS_DATA` / `HERALD_APPS_W` 可换成假目录离线测(桩掉 `herald_sys`、`stat -c %C`、`chcon`)。
已测:合法命令、白名单外、参数越界、符号链接 / FIFO / 属主不对的请求、装在 /data/app、回包位置预置符号链接。
