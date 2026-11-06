# 清单 · google-camera — Google 相机

## 做什么

删掉 Google 相机(`GoogleCamera`)、Pixel 相机服务(`PixelCameraServices`)和后台相机服务(`PersistentBackgroundCameraServices`)。**删完系统里没有相机应用**,用户自己从别处装。

## 原理

用户 2026-10-26:系统里的 Pixel 相机在 TB321FU 上用不了(相机 HAL 是联想的,Pixel 相机依赖 Pixel 专属接口),所以要删。`PersistentBackgroundCameraServices` 在 `system_ext/app`,是 Pixel 相机的常驻配套服务;`system_ext` 里其余东西一个不动。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

三项在这套 Mystic 底包里都在。想保留 Google 相机就删掉 `lists/google-camera.list`。

## 验证

桌面没有相机图标;`adb shell pm list packages | grep -i camera` 里没有 `com.google.android.GoogleCamera`、`com.google.android.apps.camera.services`。
