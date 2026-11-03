# overlay-idmap-reset

## 做什么

开机最早阶段(`post-fs-data`)用 init 的 `rm` 删掉**我们自己 overlay 在 `/data/resource-cache` 里的旧 idmap**,让系统重新生成。

## 原理(V69/V70 的教训)

静态 overlay 要先有 idmap(`/data/resource-cache/system@product@overlay@<文件名>.apk@idmap`)才能生效,由 `idmap2d` 生成。保数据升级时旧 idmap 会留在 /data 里。V68、V69 开机循环时 idmap2d 被打断,留下了写了一半的 idmap;之后 `idmap2d` 读到这种文件就 `failed to parse idmap header` 并崩溃(`OverlayManager: service 'idmap' died`),对应 overlay 永远是 `STATE_NO_IDMAP`,而且 idmap2d 每次读到它都崩一次。设备端没有 root 就清不掉(herald 后端没有删文件的命令,也不该有)。

所以在 zygote 和 system_server 起来之前,由 init 把这些文件删掉:
- 只删 `files/overlays.txt` 里列的(我们自己的 overlay,含历史文件名),不碰系统别的 idmap。
- 每次开机都删。idmap 很小,重新生成是毫秒级,而且 V69 这样的"全新文件名第一次开机"本来就是没有 idmap 的状态,系统能正常处理。
- init 默认没有删这类文件的权限,模块通过 `cil_append` 给 init 加了对 `resourcecache_data_file` 的 `unlink` 等权限(只这一类文件)。

## 改动清单

- 加 `system/etc/init/tb321fu-idmap-reset.rc`(0644 root:root `system_file`)。
- `plat_sepolicy.cil` 追加 4 行 allow(`cil_append` 会让开机时 init 重编策略)。

## 输入 / 依赖

无。要新增或改名 overlay,把文件名(不带 .apk)加到 `files/overlays.txt`。

## 换底包注意

依赖 `resourcecache_data_file` 这个 SELinux 类型和 `/data/resource-cache` 路径,Android 10 起都是这样。

## 验证

`adb shell cmd overlay list --user 0 | findstr tb321fu` 每个都是 `[x]`;`adb logcat -d -s idmap2d OverlayManager` 里没有 `failed to parse idmap header` 和 `service 'idmap' died`。
