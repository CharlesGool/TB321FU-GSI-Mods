# devopts-hide/hook — 按 App 隐藏开发者选项 / ADB 状态

**状态:写好了,单独构建和叠加构建(`spoof/app-spoof`、`statusbar-netspeed/display`、`devopts-hide/control`、`stale-boot-image`)都通过,还没上真机。**

名单里的 App(或者"除白名单和系统应用外的所有 App")读下面这些设置时,看到的值一律是 0:
`development_settings_enabled`、`adb_enabled`、`adb_wifi_enabled`、`wait_for_debugger`、`mock_location`。
设置 App 本身、`adb shell settings get` 这类不是 App 进程的读取不受影响,真实值照旧。

## 原理

和 `spoof/app-spoof` 同一套办法:framework 里加一个只用公开 API 的类,smali 在四个方法开头插调用。

| 位置 | 调用 | 作用 |
|---|---|---|
| `ZygoteInit.main` 开头 | `SettingsCompatHelper.init()` | zygote(root)fork 之前读一次 `/data/system/settings_compat.conf`,存进静态字段;App 进程继承内存,自己读不到文件 |
| `Instrumentation.newApplication` 两个重载开头 | `SettingsCompatHelper.onApp(context)` | 进程名或包名命中规则 → 把本进程标成"要隐藏" |
| `Settings$NameValueCache.getStringForUser` 开头 | `SettingsCompatHelper.over(name)` | 被标记的进程读到名单里的设置项,直接返回伪装值;没标记的进程只多一次 volatile 读 |

`Settings.Global/Secure` 的所有 `getString/getInt/getLong…` 最终都走 `getStringForUser`,所以只钩这一个方法。

## 配置文件

`/data/system/settings_compat.conf`(root 0600,标签 `settings_compat_file`),由 `devopts-hide/control` 写;不存在 = 什么都不做,整机行为和没装一样。

```
MODE=list|all           list = 只对 TARGET 里的 App 隐藏;all = 对除 TARGET(白名单)和系统应用以外的所有 App 隐藏
TARGET=<进程名或包名>     可多行;进程名带 :xxx 后缀的子进程按包名命中
OVER.<设置项>=<值>        被隐藏的进程读这个设置项时看到的值
```

all 模式的"系统应用"= uid < 10000 或带 `FLAG_SYSTEM` / `FLAG_UPDATED_SYSTEM_APP` 的包,这样"设置"还能显示真实的开发者选项。

## 依赖和顺序

无依赖。改了 `framework.jar`,必须排在 `stale-boot-image` 前面;和 `spoof/app-spoof`、`statusbar-netspeed/display` 的先后无所谓(各自从当前 jar 读、各加一份新 dex,编号自动接续)。
配置文件的标签靠 `plat_file_contexts` 里的一条规则固定,restorecon 之后也不会丢;zygote 读它的 SELinux 规则在 `sepolicy.cil`。

## 输入(device.conf)

`APKTOOL_JAR`、`R8_JAR`、`ANDROID_JAR`(都已有)。

## 测试

`patches/optional/devopts-hide/parts/001.hook/test/HelperTest.java`:解析和命中规则 20 项,纯 JVM。
`toolkit/test-hide-plugin.sh` 会再用这个解析器读一遍真实生成的配置文件。

## 限制

- **只管 Java 层的 Settings 读取**。直接读系统属性(`ro.debuggable`、`sys.usb.state`)、跑 `getprop` 子进程、读 USB 状态粘性广播里的 `adb=true`、探测 `/sys` 的检测方式都拦不到。
  系统属性的 Java 入口 `SystemProperties` 是隐藏 API,普通 App 反射不了,所以没钩。
- 规则只在开机时读,改了要重启。
- 名单里是系统应用时(list 模式)它也会被隐藏,可能影响它自己的功能。
- 钩子类名是 `com.android.internal.os.SettingsCompatHelper`。检测软件如果专门查 framework 里的类,能查到(和 `spoof/app-spoof` 一样)。

## 没在真机上核对的项

- 改完 framework.jar 后第一次开机会重新生成 boot image,慢一次。
- `getStringForUser` 开头的早返回在 ART 里是否被内联/优化改变行为(smali 等价性已验证,运行时没验证)。
- 名单里的 App 实际读 `Settings.Global.ADB_ENABLED` 得到 0。
