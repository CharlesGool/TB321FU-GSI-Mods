# 清单 · dock-hub — 底座 / Hub 模式

## 做什么

删掉 Pixel Tablet 底座(Hub 模式)相关组件:DockManagerPrebuilt、DockSetup,DockSetup 的两个 overlay,DockManager 的权限 xml,`pixel_docking_experience_2022` sysconfig。共 6 项。

## 原理

Pixel Tablet 配一个充电底座,放上去进入 Hub 模式(智能家居面板)。TB321FU 没有这个底座。DockManager 是管理底座的常驻服务,DockSetup 是 Hub 模式设置向导;两个 overlay(`product/overlay/DockSetup__tangorpro__auto_generated_rro_product.apk`、`mystic/vo/DockSetup__tangorpro__auto_generated_rro_vendor.apk`)是 DockSetup 的资源覆盖;`com.google.android.apps.nest.dockmanager.app.xml` 是 DockManager 的权限/省电白名单,`pixel_docking_experience_2022.xml` 是 Pixel 底座体验的 sysconfig。主体删了,这些配套项留着就是死引用。依据 test-results/20261027-0240-overlay-audit.md。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

6 项在这套 Mystic 底包里都在。注意两个 overlay 的文件名带 `tangorpro`,别的 GSI 里机型代号不同就对不上、被跳过;其中一个在 `mystic/vo/`(Mystic 自己加的目录),别的 GSI 没有这个目录。路径一个都不存在时模块什么也不做。

## 验证

`adb shell pm list packages | grep -i dock` 没有 `dockmanager` / `docksetup`;设置里没有"底座"/Hub 模式入口。
