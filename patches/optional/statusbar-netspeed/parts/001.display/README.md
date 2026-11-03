# statusbar-netspeed/display — 状态栏网速显示

在状态栏里显示实时网速(默认右侧、系统图标前面,上行一行下行一行)。**不改 SystemUI 的 APK**,所以也不涉及签名:
SystemUI 是 Google 平台签名,我们没有这把私钥;自签名的 priv-app 拿不到 `signature` 级权限(`faceunlock` 那次真机验证过),SystemUI 需要的 `STATUS_BAR_SERVICE` 就是这一级。
改成在 framework 里加一个只在 SystemUI 进程里运行的小类,从窗口树里找到状态栏,把一个 TextView 插进去。

## 原理

1. `framework.jar` 新加一份 dex(`com.android.internal.util.HeraldNetSpeed`、`HeraldNetSpeedFormat`,Java 源码在 `src/java/`,构建时 javac + d8 现编),
   在 `Instrumentation.callApplicationOnCreate` 开头插一处调用(`patch_framework.py`)。和 `spoof/app-spoof` 是同一套办法,两个模块的钩子在不同方法上,互不冲突。
2. 每个 App 进程创建 Application 时会走进钩子,第一件事比包名,不是 `com.android.systemui` 立刻返回,开销只是一次字符串比较。
3. SystemUI 进程里:8 秒后起一个主线程定时器(每秒一次)。反射 `WindowManagerGlobal` 取所有窗口根视图,找到类名是 `PhoneStatusBarView` 的那棵(framework 自己的代码不受隐藏 API 限制),
   按 id 名找到容器,把 TextView 插进去:
   - `end`(默认):`status_bar_end_side_content` 里、`system_icons` 之前;
   - `start`:`status_bar_start_side_except_heads_up` 里、时钟 `clock` 之后。
4. 数据用 `TrafficStats.getTotalRxBytes/TxBytes`(所有非回环网卡合计),相邻两次的差除以时间。熄屏或状态栏不可见时不采样,亮屏后第一秒显示 0。
5. 字号取时钟的 0.58 倍(两行)或 0.85 倍(一行),颜色和字体取时钟的当前值,所以跟着深浅色图标变色。宽度按最长样例固定,数字跳动时旁边的图标不抖。
6. 状态栏被 SystemUI 重建(切换主题、配置变化)时,发现旧视图不在窗口里就重新找、重新插。
7. 任何一步失败(找不到状态栏、反射出错、容器不是 LinearLayout)都只是不显示,异常被捕获并写 logcat(tag `HeraldNetSpeed`),不会让 SystemUI 崩。

## 设置

`Settings.Global`,字符串,没设就用默认值。不装 `statusbar-netspeed/control` 也能用 `adb shell settings put global <键> <值>` 改:

| 键 | 值 | 默认 |
|---|---|---|
| `herald_netspeed` | `0` 关;其他 = 开 | 开 |
| `herald_netspeed_pos` | `start` 左边时钟后 / `end` 右边系统图标前 | `end` |
| `herald_netspeed_mode` | `both` 上下行两行 / `down` 只下行 / `total` 合计 | `both` |
| `herald_netspeed_unit` | `bits` 比特制(b/Kb/Mb) / 其他 字节制(B/KB/MB) | 字节制 |

控制命令见 [`../speed-control/`](../002.control/)(`heraldctl netspeed …`)。

## 依赖和顺序

无依赖(不需要 herald)。改了 `framework.jar`,所以必须排在 `stale-boot-image` 前面;和 `spoof/app-spoof`、`build-consistency-dialog-fix` 的先后无所谓(各自从当前 jar 读、各加一份新 dex)。

## 输入(device.conf)

`APKTOOL_JAR`、`R8_JAR`、`ANDROID_JAR`(都已有)。

## 限制

- 开了 VPN 时,隧道网卡和底层网卡的流量会各算一份,速度偏大。
- 依赖 SystemUITitan 的布局(容器和锚点的 id 名);换了 SystemUI 要核对 `status_bar.xml` 里 `status_bar_end_side_content`、`system_icons`、`status_bar_start_side_except_heads_up`、`clock`,对不上只会不显示。
- 锁屏界面的状态栏是另一棵视图,这里没处理,不显示网速。
- 状态栏高度有限,两行模式字号很小(时钟的 0.58 倍);嫌小用 `mode down` 或 `total` 一行显示。

## 没在真机上核对的项

- 钩子进了 SystemUI 之后,8 秒后能不能找到状态栏并插进去(`logcat -s HeraldNetSpeed` 看有没有异常)。
- 两行文字在平板状态栏高度里有没有被裁。
- `Settings.Global` 的读取是否在 SystemUI 进程里正常(默认值路径不依赖它)。
- 改了 framework.jar 后第一次开机慢一次(boot image 重新生成,`stale-boot-image` 的既有行为)。

## 测试

- `test/FormatTest.java`:格式化函数,纯 Java,电脑上直接跑(见下面命令)。
- 构建验证:`toolkit/test-modules.sh <device.conf> --solo statusbar-netspeed/display`(会反编译真实 framework.jar,插钩子、回编、核对)。

```bash
J=/usr/lib/jvm/java-17-openjdk-amd64/bin; W=$(mktemp -d)
$J/javac -d $W/c $(find src/java -name '*Format.java') && $J/javac -d $W/t -cp $W/c test/FormatTest.java && $J/java -cp $W/c:$W/t FormatTest
```
