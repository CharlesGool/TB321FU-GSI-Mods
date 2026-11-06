# zuicamera/memory-check — 修拍照前"内存已满"误判

## 现象

DP11(A17)test-v1.3 真机:预览、录像正常,拍照模式下快门大多没反应(照片偶尔能存上)。每次按快门的日志:

```
ZCAM_ImageCaptureManage: isMemoryFull max:512/512,preadd:9.5251465,reduce_preadd:9.5251465
ZCAM_ImageCaptureManage: isMemoryFull result:true
ZCAM_ImageCaptureManage: hasFullQueue true
ZCAM_MultiBaseModule: Not taking picture since Camera is closed or capture is not allowed.
```

而相机堆实际只用了约 20MB,队列 0 张。

## 原理

`ImageCaptureManager.isMemoryFull()`:`maxMemory() - totalMemory() <= 预估占用 + 50MB` 就判满。
`totalMemory()` 是 ART 当前的堆**容量**(已向系统要的),不是已用量。A17 上相机进程的堆容量会长到上限(512/512),
差值恒为 0 → 每次判满 → `hasFullQueue` 为真 → 放弃拍照。录像不走这条检查,所以录像正常。

补丁(`files/patch_memory_check.py`)在判断那段 `totalMemory()` 后面减去 `freeMemory()`,即按 `max - (total - free)` 算真实剩余。
日志里那行 `max:` 的打印没改(仍显示容量)。找不到预期的那一处就构建失败(APK 版本变了)。

## 改动清单

- **修改** `system/priv-app/ZuiCamera/ZuiCamera.apk`(重签,0644,`system_file`)。

## 依赖和顺序

在 `001.app` 之后;和 003~006 各自改一次 APK,互不影响。A15 线上判断只会更准,无副作用。
