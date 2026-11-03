# custom-font/hook — 自定义系统字体

**状态:写好了,单独构建和叠加构建(带 `spoof/app-spoof`、`statusbar-netspeed/display`、`devopts-hide/hook` 等四个改 framework.jar 的模块)都通过,还没上真机。**

用户上传或预置的字体包放在 `/data/fonts/herald/`,系统启动时改读它。**不用 bind 挂载**(不增加 `/system` 叠加挂载,检测软件看不到),**不占 system 空间**(原先估的 105MiB 余量不是问题,字体包全在 /data)。

## 原理

Android 12 起,字体表由 system_server 的 `FontManagerService` 建好,打包成共享内存发给每个 App 进程。建表入口是
`SystemFonts.getSystemFontConfigInternal(fontsXml, systemFontDir, oemXml, productFontDir, …)`:前四个参数是路径,默认 `/system/etc/font_fallback.xml`、`/system/fonts/`、`/product/etc/fonts_customization.xml`、`/product/fonts/`。

`patch_framework.py` 在它开头插四个调用,每个参数交给 `FontCompatHelper` 换一遍:有可用字体包就换成包里的路径,没有就原样返回(整机行为和没装一样)。
"可用"要过三关:`/data/fonts/herald/active` 里的包名合法且目录和 `font_fallback.xml` 都读得到;用系统自己的 `FontListParser.parse` 反射试解析一次,不抛异常且字体族不为空;任何一步失败都回到系统原配置。结论每个进程只算一次。

## 字体包

`/data/fonts/herald/packs/<名字>/`:
- `font_fallback.xml`:必须有,格式和系统原版一样;字体文件都放在同一个目录(没改的系统字体由 `custom-font/control` 做成指向 `/system/fonts`、`/product/fonts` 的符号链接)。
- `fonts_customization.xml`:可选;有就替换 `/product/etc/fonts_customization.xml`(Google Sans 系列在这里定义),字体目录同样是包目录。

当前用哪个包写在 `/data/fonts/herald/active`。管理命令见 `custom-font/control`,做包见 `toolkit/make-font-pack.py`。

## 依赖和顺序

无依赖。改了 `framework.jar`,必须排在 `stale-boot-image` 前面;和其他改 framework.jar 的模块先后无所谓(新 dex 编号自动接续)。
不需要新的 SELinux 规则:包目录标签 `font_data_file`(和系统自带的 `/data/fonts/files` 同类型),system_server 本来就能读。

## 输入(device.conf)

`APKTOOL_JAR`、`R8_JAR`、`ANDROID_JAR`(都已有)。

## 测试

`patches/optional/custom-font/parts/001.hook/test/FontHelperTest.java`:包名校验 14 项,纯 JVM。解析和切换逻辑靠真机验证。

## 限制

- 字体表在 system_server 启动时建,**切换要重启**;改完 `active` 之后当前开着的进程不变。
- **WebView / Chrome 页面里的系统字体不变**:它们自己读 `/system/etc/fonts.xml`。App 里用 `Typeface`/系统字体的文字(包括系统界面)会变。
- 不支持 `.ttc` 字体集合(做包工具会拒绝);emoji、阿拉伯文等其他脚本的 fallback 字体需要时手改 xml。
- 一个有问题的字体文件(文件头对但内容坏)可能让 native 层崩溃,解析试探拦不住;`custom-font/control` 的开机保护会在"开机没走完"时自动撤回包,但如果崩在 system_server 之前就起不来的话还是要刷机恢复。

## 没在真机上核对的项

- 包目录里的符号链接(指向 `/system/fonts`)被 system_server 打开、mmap 是否正常。
- 打包发给 App 的共享内存里,字体数据是复制进去还是按文件映射;后者要求 App 也读得到 `font_data_file`。
- 实际换字体后系统界面、设置里的文字是否都跟着变;Google Sans 替换后启动器和时钟的显示。
