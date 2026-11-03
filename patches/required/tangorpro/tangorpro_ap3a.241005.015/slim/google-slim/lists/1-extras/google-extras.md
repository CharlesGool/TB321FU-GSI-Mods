# 清单 · google-extras — Google 冷门应用

## 做什么

删掉不是人人都用的 Google 预装应用:15 项,见同名 `.list`。

## 原理

能从 Play 装回来,而且这批多数用的人不多(YouTube 全家、Meet、Home),或依赖 Pixel 系统接口、在 TB321FU 上没有意义(Wellbeing、Health、ARCore、DevicePolicy、PixelLiveWallpaper)。system 分区大小固定,删掉才放得下别的功能,所以这份是必选。日常会用的 Google 应用不在这里。

## 改动清单

删除 `google-extras.list` 里的目录/文件,没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

应用目录名带版本号,版本一变路径就对不上、被当成"底包里没有"而跳过;换底包后看日志里"底包里没有 N 项"的 N 有没有变多。这套 Mystic 底包里没有 `MeetPrebuilt_20240414`、`HealthIntelligencePrebuilt-1762` 两项。

## 验证

开机后桌面应用列表里没有这些应用,设置/Play/Chrome/文件还在。
