# 清单 · google-assistant — Google 助理 / Google 应用

## 做什么

删掉 Google 应用(Velvet,即"Google"搜索/助理主程序)、它的资源包 `NgaResources`,以及两个唤醒词录入程序(`HotwordEnrollmentOKGoogleFUSIONPro`、`HotwordEnrollmentXGoogleFUSIONPro`)。

## 原理

Velvet 是 Google 助理/搜索的主程序,它和语音唤醒("OK Google")的录入程序、资源包是一套,常驻且占内存。能从 Play 装回来,所以和其它 Google 应用一样全删。四项一起删才干净:只删 Velvet 留着两个唤醒词录入程序没有意义。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

四项在这套 Mystic 底包里都在。Velvet 和 HotwordEnrollment 在 `product/priv-app`,`NgaResources` 在 `product/app`。注意 `device.xml`/permissions 里对 Velvet 的引用不会被清理,只是引用一个不存在的包,无害。

## 验证

开机后长按电源键/说 "OK Google" 没有助理;`adb shell pm list packages | grep -i velvet` 为空(包名 `com.google.android.googlequicksearchbox`)。
