# custom-font/control — `heraldctl font`

字体包管理。**状态:写好了,插件测试 106 项通过(dash 和 busybox sh 各一遍),单独和叠加构建通过,还没上真机。** 钩子在 `custom-font/hook`,不装它,选了包也没有可见效果。

```bash
heraldctl font                              # active、packs、reboot_required、reverted、root
heraldctl font list                         # 每个包:valid、active、kb
heraldctl font install /data/local/tmp/wenkai.zip [名字]   # zip(顶层要有 font_fallback.xml)或目录;来源只能在 /data/local/tmp/、/sdcard/ 下
heraldctl font use wenkai                   # 选用(先补链接、打标签、查文件齐全),然后重启生效
heraldctl font reset                        # 回系统字体,重启生效
heraldctl font remove wenkai                # 删包(正在用的不让删)
heraldctl font check wenkai                 # 缺哪些文件
```

字体包用 `toolkit/make-font-pack.py` 在电脑上做。

## 怎么落地

- `install` 解到 `/data/fonts/herald/packs/.tmp-<pid>`,检查顶层有 `font_fallback.xml`、解开后不超过 256MB,再改名成 `packs/<名字>`。
- `use` / `install` 会把 `/system/fonts`、`/product/fonts` 里包没有的文件做成符号链接(`ln -s`),再 `chcon -R -h u:object_r:font_data_file:s0`(`-h` 不跟随符号链接,不会去改系统文件的标签),然后核对 xml 引用的每个字体文件都在。
- `active` 是一行包名。`reboot_required=1` = 它和开机时那份(`boot_active`)不一样。

## 开机保护

`herald-font.sh` 由 init 的两个一次性服务调用:
- `boot`(post-fs-data,system_server 之前):上次留下了 `boot_try`(= 选了包但没走到 `sys.boot_completed`)→ 撤回 `active`、包名记进 `reverted`;否则 `active` 存在就放一个 `boot_try`。
- `ok`(`sys.boot_completed=1` 之后):删 `boot_try`。

所以一个让开机卡住/重启的字体包,会在下一次开机时被自动撤回,回到系统字体。`status` 里 `reverted=<包名>` 提示发生过。代价:选了包之后第一次开机中途手动断电重启,也会被撤回,再 `font use` 一次即可。

## 依赖和顺序

`require_mod required/general/herald-core`。接口见 [../../../../doc/herald-backend-api.md](../../../../../../doc/herald-backend-api.md) 的 font 一节。

## 测试

```bash
bash toolkit/test-font-plugin.sh
```
