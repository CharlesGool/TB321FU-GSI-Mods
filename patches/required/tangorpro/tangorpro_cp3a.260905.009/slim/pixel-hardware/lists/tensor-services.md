# 清单 · tensor-services — Tensor 专属服务

## 做什么

删掉 AICorePrebuilt、EnsemblePrebuilt-stub、MaestroPrebuilt、DiagnosticsToolPrebuilt、BetterBugStub 五个 priv-app。

## 原理

这些是依赖 Google Tensor 芯片/Pixel 系统接口的服务:AICore(端上 AI)、Ensemble、Maestro、诊断工具、BetterBug(Pixel 反馈)。TB321FU 是骁龙平台,没有对应硬件和 HAL,留着只是常驻、报错。

实现:`toolkit/lib/removelist.sh` 的 `apply_lists` 命中本清单后,用 `remove_list` 逐行删 本清单(同名 `.list`) 里的路径(相对镜像里的 `system/`)。路径不存在的跳过并计数,一项都没删到也不报错,只是什么也不做。

## 改动清单

删除 本清单(同名 `.list`) 里的目录/文件,见该文件。没有新增或修改任何文件。

## 输入

无。

## 依赖和顺序

无依赖,和同组其它模块互不影响,顺序随意。

## 换底包注意

五项在这套 Mystic 底包里都在,都在 `product/priv-app`。AICore 是别的应用(如部分 Google 应用的端上 AI 功能)的依赖,删掉后那些功能不可用,这是预期的。

## 验证

`adb shell pm list packages | grep -iE "aicore|ensemble|maestro|diagnostics|betterbug"` 里没有这几个。
