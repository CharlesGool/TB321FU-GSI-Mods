# 清单 · google-apps — Google 应用

## 做什么

删掉 Google 的预装应用:计算器、日历、通讯录、Meet、拨号、健康、短信、Tips、Drive、Keep、地图、相册、Gmail、图书、视频、YouTube / YouTube Kids / YouTube Music、时钟、TTS、ARCore、DevicePolicy、WallpaperEmoji、录音机、天气、Wellbeing、Home、PixelLiveWallpaper、LocationHistory 等 29 项。

## 原理

这些都能从 Play 装回来,而且 TB321FU 上用 Pixel 版的没有意义(Pixel 天气、Pixel 录音机、Wellbeing 等依赖 Pixel 系统接口)。原则是:Google 应用全删,用户要用自己从 Play 装。清单里前 8 项(计算器/日历/通讯录/Meet/拨号/健康/短信/Tips)来自早先 komodo-15 修改版的精简清单,其余是用户后来加的。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

这套 Mystic 底包里**没有** `MeetPrebuilt_20240414`、`GoogleDialer`、`HealthIntelligencePrebuilt-1762` 三项(实测),其余 26 项都在。没有的会 log "底包里没有 3 项",不报错。别的 GSI 里应用目录名带版本号(如 `_85005407`),版本号一变路径就对不上、被当成"底包里没有"而跳过 —— 换底包后看日志里"底包里没有 N 项"的 N 有没有变多,变多了就去核对 本清单(同名 `.list`)。

## 验证

开机后看桌面应用列表:这些应用都不在了,设置/Play/Chrome/文件还在。
