# no-auth — 免授权 ADB

- `system/build.prop`:`ro.adb.secure=0`(连电脑不弹授权框)。
- `system/system_ext/etc/build.prop`:`ro.adb.secure=0`(`debug-off` 在这里也写了 1,要一起改回去)。
- 不碰 `ro.debuggable`、`ro.secure`:`adb shell` 还是 shell 用户,要 root 用 `heraldctl rsh`。

仅用于开发调试镜像。没上真机验证:接电脑不弹授权框。
