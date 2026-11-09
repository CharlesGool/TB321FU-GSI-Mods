# qs-auto-brightness:快捷设置里的"自动亮度"开关

AOSP / Pixel 的 SystemUI 没有自适应亮度的快捷设置开关。这里装一个只有 `TileService` 的小系统 App(`com.lenovo.tb321fu.qsbrightness`):

- 点一下在 `Settings.System.SCREEN_BRIGHTNESS_MODE` 的 0(手动)和 1(自动)之间切换,副标题显示"开启 / 关闭";
- 面板打开时监听这个设置,在设置 → 显示里改了也会同步;
- `WRITE_SETTINGS` 对系统分区的 App 自动授予(signature|preinstalled|appop),不用用户去授权。

装好后:下拉快捷设置 → 编辑 → 把"自动亮度"拖进去,或者
```bash
adb shell cmd statusbar add-tile com.lenovo.tb321fu.qsbrightness/.AutoBrightnessTile
```

源码在 `app/`,`app/build-linux.sh` 在构建容器里编;签名 key 在 `app/keystore/`,不进仓库。

长按开关进 **设置 → 显示和触控**(V1.1):SystemUI 长按第三方开关时打开本包响应 `QS_TILE_PREFERENCES` 的 Activity(没有就打开应用信息页),
开关只能指向自己包里的 Activity,所以 `TilePrefsActivity` 是个无界面的跳转页:转到 `Settings.ACTION_DISPLAY_SETTINGS` 后立刻结束(不进最近任务、不留空白页)。
