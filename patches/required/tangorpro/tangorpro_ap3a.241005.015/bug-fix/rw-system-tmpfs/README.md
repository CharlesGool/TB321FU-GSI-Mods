# rw-system-tmpfs

## 做什么

去掉 phh 的 `rw-system.sh` 多出来的"可写 tmpfs 盖在 /vendor 上"的挂载。

## 原理

phh 的 `/system/bin/rw-system.sh` 会把 `/vendor/lib{,64}/hw/com.qti.chi.override.so` 和 `/vendor/lib{,64}/libVD*` 复制到 tmpfs(`/mnt/phh`),用 sed 把 `ro.product.manufacturer/brand/model` 换成 `sys.phh.*`,再 bind 回 /vendor。TB321FU 的这些库里根本没有这三个字符串,sed 什么也不改,结果只是凭空多出一个从可写 tmpfs bind 到 /vendor 的挂载,检测器报 `SYSTEM_PARTITION_WRITABLE` / `ACTIVE_STACKED_FS_OVER_SYSTEM fs=tmpfs`。

在循环里加一行:文件里没有这几个字符串就 `continue` 跳过。需要这个处理的设备行为不变。

## 改动清单

- `system/bin/rw-system.sh`:在 `for f in ...` 循环的 `[ ! -f $f ] && continue` 后插入一行 `grep -qE 'ro\.product\.(manufacturer|brand|model)' "$f" || continue`。

## 输入 / 依赖

无。

## 换底包注意

`fix_rw_system.py` 要求锚点文本在文件里正好出现一次;phh 脚本改版后锚点变了会直接失败,按新脚本更新锚点。底包没有 rw-system.sh 就跳过。

## 验证

```bash
adb shell mount | grep -E "tmpfs.*vendor|/mnt/phh"   # 没有 bind 到 /vendor 的 tmpfs
```
