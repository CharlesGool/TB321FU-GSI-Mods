# statusbar-netspeed/control — 状态栏网速的控制命令

给后端加 `netspeed` 命令、给 `heraldctl` 加 `netspeed` 子命令,读写 `Settings.Global` 里 `statusbar-netspeed/display` 用的四个键。依赖 `herald-core`;网速本身由 [`statusbar-netspeed/display`](../001.display/) 画。

```
heraldctl netspeed [status]
heraldctl netspeed on | off
heraldctl netspeed pos start|end
heraldctl netspeed mode both|down|total
heraldctl netspeed unit bytes|bits
heraldctl netspeed reset
```

`status` 回包:`ok 状态栏网速` + `enabled=0|1` `pos=start|end` `mode=both|down|total` `unit=bytes|bits`。没设过的键按默认值显示(开、end、both、bytes)。
改完 1 秒左右生效(状态栏每秒读一次设置)。接口细节在 `doc/herald-backend-api.md` 的"状态栏网速"一节。

## 没在真机上核对的项

- 从 broker(herald 域)用 `settings put global` 写 `herald_netspeed*` 是否被放行(`refresh-rate` 写 `Settings.System` 已验证过同一条路,这里是 `global`,理论上一样)。

## 测试

`toolkit/test-netspeed-plugin.sh`(dash 和 busybox sh,`settings` 命令是桩,不碰真机)。
