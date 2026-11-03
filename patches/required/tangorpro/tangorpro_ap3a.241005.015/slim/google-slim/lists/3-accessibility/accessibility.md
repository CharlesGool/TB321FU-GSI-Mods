# 清单 · accessibility — 无障碍应用

## 做什么

删掉 Google 的无障碍应用:TalkBack(`talkback`)、声音放大器(`SoundAmplifierPrebuilt`)、语音控制(`VoiceAccessPrebuilt`)、手写(`ScribePrebuilt`)、开关控制(`SwitchAccessPrebuilt`)。

## 原理

这些是 Google 的独立无障碍应用,能从 Play 装回来(TalkBack 等在 Play 里叫 "Android Accessibility Suite" / 单独的应用)。系统自带的无障碍框架(设置里的无障碍页、AccessibilityService)不受影响。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错(见组 README)。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件(每行一项,带注释)。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

**需要读屏的用户不要用这个模块**:不打 `optional/slim/accessibility`。路径里带版本号(`_v4.7.638126989`、`_1.15.0.629986523`、`_v7.0.633113815`),换底包后版本号变了会被当成"底包里没有"而跳过。

## 验证

设置 → 无障碍 → 已下载的应用:没有 TalkBack、语音控制等。
