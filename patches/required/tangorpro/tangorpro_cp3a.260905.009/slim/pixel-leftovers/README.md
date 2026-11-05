# slim/pixel-leftovers — Pixel 专属但本机用不上的应用和数据

通用精简脚本 + 本补丁自带的清单。必须打(所有 GSI)。

| 清单 | 删什么 |
|---|---|
| [play-auto-install](lists/play-auto-install.md) | Play 自动安装配置(不删会把 Google 应用装回来) |
| [ambient-music](lists/ambient-music.md) | "正在播放"歌曲库(52M,要 Pixel 硬件) |
| [google-camera](lists/google-camera.md) | Pixel 相机(联想相机 HAL 用不了) |
| [kids](lists/kids.md) | 儿童模式 |

## 怎么维护

删什么由 `lists/*.list` 决定(一行一个路径,相对镜像里的 `system/`;`#` 注释;可以带通配符,版本号写成 `Xxx_*`);每份清单配一个同名 `.md` 讲为什么删。删不到的条目只记日志(`(没有) 路径`),日志末尾每份清单一行统计,换底包后看"底包里没有 N 项"的 N 变大了就去核对。通用脚本见 `toolkit/lib/removelist.sh`。
