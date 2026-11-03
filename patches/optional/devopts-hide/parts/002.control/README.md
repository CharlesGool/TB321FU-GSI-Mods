# devopts-hide/control — `heraldctl hide`

按 App 隐藏的规则管理。现在只有 `devopts`(开发者选项 / ADB 状态,钩子在 `devopts-hide/hook`);以后加应用列表隐藏时在同一个命令下加 `applist`。
**状态:写好了,插件测试 122 项通过(dash 和 busybox sh 各一遍),单独和叠加构建通过,还没上真机。**

```bash
heraldctl hide                         # 各项概况(devopts=on|off)
heraldctl hide devopts                 # 状态:enabled、mode、names、rules_file、reboot_required、keys
heraldctl hide devopts add com.xxx     # 名单加一个(进程名或包名;上限 500 条)
heraldctl hide devopts remove com.xxx
heraldctl hide devopts list
heraldctl hide devopts on | off
heraldctl hide devopts mode list|all   # list = 只对名单里的 App 隐藏(默认);all = 名单是白名单,其余非系统 App 全隐藏
heraldctl hide devopts reset           # 关闭、list 模式、名单清空
```

**改完都要重启生效**(回包带 `reboot-required`);`reboot_required=1` 表示现在的规则和开机时那份不一样。
list 模式名单为空时 `on` 不会写配置文件,回包提示先 add。

## 怎么落地

- 规则源:`/data/adb/herald/devhide.conf`(`enabled=`、`mode=`)和 `devhide.names`。
- `herald-devopts-hide.sh` 把规则编成 `/data/system/settings_compat.conf`(5 个设置项固定写 0)并 chcon:broker 每次改完直接调它,开机 post-fs-data 由 init 一次性服务 `herald_devhide_boot`(zygote 启动之前)再调一次,并把配置存一份副本 `devhide.boot` 供 `reboot_required` 比较。
- 规则无效(关着、或 list 模式没有名单)时删掉配置文件,钩子什么都不做。
- chcon 失败(没装 `devopts-hide/hook`,类型不存在)只记 dmesg(前缀 `herald-devhide:`),文件照写。

## 依赖和顺序

`require_mod required/general/herald-core`。不装 `devopts-hide/hook`,这里的规则写了也没有可见效果。接口见 [../../../../doc/herald-backend-api.md](../../../../../../doc/herald-backend-api.md) 的 hide 一节。

## 测试

```bash
bash toolkit/test-hide-plugin.sh
```
