# debug-off — 关调试

## 做什么

去掉 Mystic 加的调试段,让系统是 user 状态:`ro.secure=1`、`ro.adb.secure=1`(ADB 要授权)、`ro.debuggable=0`;`system/build.prop` 权限从 0600 改回 0644。

## 原理

Mystic 的 GSI 在 `system/build.prop` 里加了两段:

- `# Force ADB`:`persist.sys.usb.config=adb,mtp`、`ro.adb.secure=0`、`ro.secure=0`、`ro.debuggable=1`
- `# Logcat`:`logd.logpersistd*`

`debug_blocks.py` 把 Force ADB 段删掉(注释、下面连续的 `persist.sys.usb.config` / `ro.adb.secure` / `ro.secure` / `ro.debuggable` 行、紧跟的一个空行;只认这四个 key,不会吞掉后面别的行);Logcat 段只删注释和 `logd.logpersistd*` 行(后面可能直接接着别的属性,不能整段吞)。底包里这两段不存在(别的 GSI)就什么也不改,无害。

然后显式写 `ro.secure=1`、`ro.adb.secure=1`、`ro.debuggable=0`(system),`ro.adb.secure=1`(system_ext,没有就追加)。key 不存在就追加,因为写上安全值总是对的。

权限:Mystic 底包里 `system/build.prop` 是 `0600`,原厂和 AOSP 都是 `0644`。App 能直接读这个文件,0600 本身就是异常特征。`edit` 会保留原权限,所以 chmod 放在本模块最后一步。

## 改动清单

- 改 `system/build.prop`:删调试段;`ro.secure`、`ro.adb.secure`、`ro.debuggable`;权限 0644
- 改 `system/system_ext/etc/build.prop`:`ro.adb.secure=1`

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块顺序随意。

## 换底包注意

- 别的 GSI 没有 Mystic 的调试段:脚本打一行"找到 0 个调试段",继续往下。
- 脚本最后核对:`ro.debuggable=1` / `ro.adb.secure=0` / `ro.secure=0` 一旦还在,或者 `# Force ADB` 还在,构建失败。
- 注意:这个模块只管 build.prop。开机后 init 脚本、`persist.*` 里的调试开关不在这里。

## 验证

```bash
adb shell getprop ro.debuggable    # 0
adb shell getprop ro.secure        # 1
adb shell getprop ro.adb.secure    # 1
adb shell ls -l /system/build.prop # -rw-r--r--
```
