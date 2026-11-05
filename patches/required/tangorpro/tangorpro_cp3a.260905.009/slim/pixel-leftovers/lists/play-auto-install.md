# 清单 · play-auto-install — Play 自动安装配置

## 做什么

删掉 `PlayAutoInstallConfig`。

## 原理

开机向导结束后,Play 商店会读这个配置包,自动把一批 Google 应用(Pixel 预设的)重新装回来 —— 前面 `google-apps` 之类删得再干净,没这一项也会被装回。所以必须删。它自己没有任何功能,单独成模块是因为它的作用和"删应用"不同:它是防止应用被装回的开关。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

在这套 Mystic 底包里存在(`product/app/PlayAutoInstallConfig`)。别的 GSI 可能没有这个包,没有就跳过,无害。

## 验证

首次开机、过完开机向导,等几分钟,桌面没有被 Play 装回来的 Google 应用。
