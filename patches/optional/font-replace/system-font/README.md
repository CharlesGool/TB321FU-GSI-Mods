# system-font — 替换系统字体

打包时用 `SYSTEM_FONT` 覆盖 `system/fonts/Roboto-Regular.ttf`,不改 `font_fallback.xml` / `fonts.xml`。
默认字体是 MiSans VF 4.009(可变字体,来自 KLCOS 时期的修改包),文件在 DP11 项目 `inputs/fonts/MiSans-VF.ttf`,路径见 `conf.d/fonts.conf`。

- 生效范围:所有用 sans-serif / roboto 的文字;字体带中文字形时中文也走它。Pixel 界面的拉丁字母仍是 Google Sans。
- 检查:文件头必须是 TTF/OTF;没有 `fvar`(不是可变字体)只警告。
- 换回:重刷不带这个补丁的包。
