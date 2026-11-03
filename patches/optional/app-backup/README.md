# app-backup — App 备份 / 还原

**状态:写好了,插件测试 136 项通过(真 tar、真 cp,pm / am / restorecon 用桩;dash 和 busybox sh 各一遍),单独构建通过,还没上真机。**

备份一个应用的 **apk(含 split)+ 数据**到指定目录,或从那里还原。不做定时备份、不做整机备份。

```bash
heraldctl backup                                  # 默认目录、备份个数、最近任务
heraldctl backup dest /sdcard/MyBackup            # 设默认目录(不设 = /sdcard/HeraldBackup)
heraldctl backup app com.xxx                      # 备份(后台跑,回 job 号)
heraldctl backup app com.xxx /sdcard/Other --ext  # 指定目录;--ext 连 /sdcard/Android/data/<包名> 一起
heraldctl backup app com.xxx --no-apk             # 只备份数据;--no-data 只备份 apk
heraldctl backup job [号]                         # 任务状态:state=running|done|failed、msg
heraldctl backup list [目录]                      # 目录里的备份
heraldctl backup restore com.xxx [目录]           # 还原;应用没装就先装 apk;--reinstall 强制重装
heraldctl backup delete com.xxx [目录]
```

## 备份的样子

`<目录>/<包名>/`:
- `backup.meta`:pkg、versionName、versionCode、uid、time、apk(份数 / `system` / `none`)、data、de、ext、user=0。
- `apk/`:`base.apk` 和各个 split。系统自带且没被更新过的应用不拷 apk(`apk=system`),只备份数据。
- `data.tar`:`/data/user/0/<包名>`,不含 `cache`、`code_cache`;`data_de.tar`:`/data/user_de/0/<包名>`;`ext.tar`:`/sdcard/Android/data/<包名>`(带 `--ext`)。

先写到 `<包名>.partial`,成功后再换名,所以中途失败不会毁掉上一份备份。一个应用只留最新一份。

## 还原做了什么

1. 应用没装(或 `--reinstall`)→ `pm install`(单 apk)或 `pm install-create/-write/-commit`(有 split);备份里没有 apk 且应用没装 → 失败。
2. `am force-stop`。
3. 每个 tar:先 `tar -t` 校验能读、顶层目录是这个包名,**校验过了才清空目标目录的内容**,再解包、`chown -R` 成目标目录原来的属主、`restorecon -RF`。备份文件损坏时不动现有数据。

## 目录规则

绝对路径,只能在 `/sdcard/`、`/storage/`、`/data/media/`、`/data/local/tmp/`、`/mnt/media_rw/` 下,只许 ASCII 字母数字和 `. _ - + @ = , : %`,不含 `..`。(不支持中文目录名。)

## 依赖和顺序

`require_mod required/general/herald-core`。接口见 [../../../../doc/herald-backend-api.md](../../../../doc/herald-backend-api.md) 的 backup 一节。

## 限制

- **只做用户 0**;多用户 / 工作资料不备份。
- 一次只跑一个任务,后台脚本由 broker 起;broker 被杀会让正在跑的任务变成 failed("任务进程已退出")。
- 数据 tar 没压缩(各家 tar 对 `-z` 支持不一),大应用占空间。
- 没备份:Keystore 里的密钥(重装后失效,依赖它的应用要重新登录)、账户(AccountManager)、运行时权限授予、`/sdcard/Android/obb`。
- 应用在运行时备份会 `force-stop` 它;还原时应用会被停掉,数据可能和进程内存里的状态不一致,还原后重新打开即可。
- 应用签名和备份里的 apk 不一致时,覆盖安装会失败(`pm install -r -d` 不能换签名)。

## 没在真机上核对的项

- Android toybox `tar` 的实际行为(本测试用的是 GNU tar 和 busybox tar);`chown -R`、`restorecon -RF` 在 `herald` 域下对其他应用数据目录的效果。
- 往 `/sdcard/...` 写(FUSE)的速度和权限;`pm install` 读 `/sdcard` 里的 apk。
- 微信、银行类应用用 Keystore 绑定设备的数据,还原后是否还能用。
