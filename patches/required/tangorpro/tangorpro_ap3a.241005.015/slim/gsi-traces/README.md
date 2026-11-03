# slim/gsi-traces — GSI 工具留下的东西

> 一个补丁(`slim/gsi-traces`),内部 5 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

Mystic、phh-treble 做 GSI 时塞进来的调试件和别的机型的兼容件。全部是纯删除,互相独立。

| 部分 | 删什么 | 大小 |
|---|---|---|
| [mystic-vendor-overlays](parts/001.mystic-vendor-overlays/) | `/system/mystic`(9 个没人引用的 tangorpro vendor overlay) | 276K |
| [mystic-boot-logcat](parts/002.mystic-boot-logcat/) | `mystic.rc`(每次开机以 root 跑 logcat 写 /data 的调试服务) | 小 |
| [phh-keylayouts](parts/003.phh-keylayouts/) | `/system/phh` 里各厂商的按键布局、NFC 配置和子目录(保留 `phh/empty`) | 小 |
| [phh-remotectl](parts/004.phh-remotectl/) | phh 远程 adb 隧道服务 | 小 |
| [phh-prop-handlers](parts/005.phh-prop-handlers/) | phh 属性处理脚本,以及 `vndk.rc` 里依赖它的 `on property:` 段落 | 小 |

GSI 的其他痕迹(属性、标签)不是删除,在 [gsi-hide](../../../../general/bug-fix/gsi-hide/);phh 脚本的可写 tmpfs 在 [rw-system-tmpfs](../../bug-fix/rw-system-tmpfs/)。

## phh 相关:没动的(以及为什么)

- `rw-system.sh`(1126 行)、`vndk-detect`、`phh-on-boot.sh`、`phh-on-data.sh`、`vndk.rc` 里其余段落:约 80 个按厂商/机型的分支我们都不匹配,但里面夹着通用逻辑——`vndk-detect` 设 `persist.sys.vndk`、`/mnt/phh` tmpfs、把 `phh/empty` 盖到 vendor 的库上、`phh-on-boot.sh` 里的 `bootctl mark-boot-successful`(A/B 槽标记成功)和 wifi supplicant 配置、`hostapd.conf` 的属主(热点用)、`ro.sf.lcd_density` 变了重启 surfaceflinger、`watchdogd-gsi`。拆开动要上机验证,先不做。
- `misctrl`、`kcmdlinectrl`、`mtectrl`:AOSP 自带(Android 15 的 misc 分区工具),不是 phh 的。
- `busybox_phh`(1MB):只被 `rw-system.sh` 里的 IMS 检测用一次,随 `rw-system.sh` 一起处理。

## 注意

phh 三个**没在真机上单独试过**:它们删的东西都是靠属性才触发、或者依赖不存在的 SELinux 域(`phhsu_daemon`,Mystic 把 phh 的 sepolicy 去掉了)的,理论上无副作用;刷后检查开机、热点、蓝牙、亮度正常。`/system/phh/empty` 必须保留(rw-system.sh 无条件地把它盖到 vendor 的 libpdx_default_transport.so 上)。
