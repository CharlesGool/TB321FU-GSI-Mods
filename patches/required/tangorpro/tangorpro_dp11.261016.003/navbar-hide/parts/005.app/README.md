# navbar-hide/app:导航栏 App + 设置里的入口

- **App** `com.lenovo.tb321fu.navbar`("导航栏",没有桌面图标):一个"隐藏导航栏"开关,经 herald-apps 通道跑 `navbar status|hide|show`(白名单 `files/com.lenovo.tb321fu.navbar.allow`)。
  只在手势导航下生效;三按钮导航时打开开关只是记下意愿,切到手势导航后由 navbar 插件的守护自动隐藏。源码在模块的 `app/`(`app/build-linux.sh`)。
- **入口**:设置 → 系统 → 导航模式 → 三按钮导航 / 手势导航 右边的齿轮,页面最下面的"导航栏 → 隐藏导航栏"。
  - 导航模式页本身是 `RadioButtonPickerFragment`(每次刷新 `removeAll()` 再用代码加单选项),齿轮页 `ButtonNavigationSettingsFragment` / `GestureNavigationSettingsFragment` 没有注册注入分类,都不能用 `IA_SETTINGS` 注入;
  - 所以用静态 RRO `tb321fu-settings-navbar.apk`(目标 `com.android.settings`,priority 326)替换这两页的 `res/xml`:内容照抄 DP11 SettingsGoogle 原文件,末尾加一个 `PreferenceCategory` + 带 `<intent>` 的 `Preference`。
  - overlay xml 要引用 Settings 的私有资源和属性:`settings-rro/build.sh` 先按真 SettingsGoogle 的资源 ID 生成一个"链接用桩包"(`build-stub.py`,资源声明成 public,枚举属性带上 enum 定义),overlay 链接它;本包 id `0x7e`、min-sdk 34(否则 aapt2 把 xml 拆成按 API 版本的两份)。
  - 带一个标量锚点 `bool/config_show_emergency_gesture_settings=true`(和默认值相同、没有别的 overlay 改它):只含 xml 的静态 overlay 可能生成不了 idmap(V69 的教训)。
- 离线已验证:两页原有内容和 SettingsGoogle 原文件按属性 ID + 值逐个一致;底包的 idmap2 对 SettingsGoogle 生成 idmap,映射 3 项。
- **换底包必须重编 RRO**(资源 ID 是这个 SettingsGoogle 的):
  ```bash
  settings-rro/build.sh <新 SettingsGoogle.apk> <apktool 解出的 res/values/attrs.xml> files/tb321fu-settings-navbar.apk
  ```
