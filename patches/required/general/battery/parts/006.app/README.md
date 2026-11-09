# battery/app:电池管理 App

`com.lenovo.tb321fu.battery`("电池管理"):入口在 **设置 → 电池**(没有桌面图标),界面按 Android 16 设置的样式手写,颜色跟随系统取色和深色模式。
内容:电量、电池健康(健康度、满电 / 设计容量、循环次数)、电池 1 / 2、实时状态、充电上限、长期插电保护、旁路充电。

- 只在打了 `required/general/herald-apps` 的底包线上装(App 经它的通道和 battery 插件说话)。
- `files/com.lenovo.tb321fu.battery.allow`:App 只能跑这几条命令。
- 读取用一条 `battery overview`(info + 三个 status);打开时先显示上次的数据,后台每 5 秒刷新。
- 源码在模块的 `app/`,`app/build-linux.sh` 在构建容器里编;签名 key 不进仓库(`app/keystore/`,以后升级用同一把)。
