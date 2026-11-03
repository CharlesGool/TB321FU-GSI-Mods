# 清单 · kids — 儿童模式

## 做什么

删掉 Kids Home(`KidsHomePrebuilt`)和 Kids Supervision(`KidsSupervisionStub`)。

## 原理

Pixel Tablet 的儿童模式。TB321FU 上用不到,并且常驻一个监督服务的 stub。能从 Play 装回来。注意 `YouTubeKidsPrebuilt` 是 YouTube Kids 应用,归 `google-apps`,不在这里。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

两项在这套 Mystic 底包里都在,都在 `product/priv-app`。

## 验证

设置里没有"儿童模式"入口;`adb shell pm list packages | grep -i kids` 里没有 `kidshome` / `kidssupervision`。
