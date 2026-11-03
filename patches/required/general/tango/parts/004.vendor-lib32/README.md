# tango/vendor-lib32

## 做什么

给 `/vendor/lib`(32 位库目录)补上 32 位 GPU / gralloc 栈。原厂 vendor 的 `lib/` 只有 DSP 库(`rfsa/adsp`),没有 32 位 Adreno 驱动,32 位 app 进程自带 HWUI,没有 EGL/GLES/Vulkan 就画不出界面。

## 原理

vendor 是只读 + AVB 保护的,不能直接加文件。办法:库放进 `system/etc/vendor-lib32/`,`on post-fs` 用 init 自带的 `mount` 把它和原厂 `/vendor/lib` 叠成只读 overlay 盖回 `/vendor/lib`:

```
mount overlay overlay /vendor/lib ro nosuid nodev lowerdir=/system/etc/vendor-lib32:/vendor/lib
```

原厂 `/vendor/lib/rfsa`、`modules` 照常可见,没有同名文件所以没有遮盖。不用 `vendor-bind`:那是"单文件盖单文件",目标要先存在,这里是新增整套文件。
用 init 自己的 `mount` 而不是脚本,不新增 SELinux 域;设备守护靠 rc 触发条件 `property:ro.product.vendor.device=TB321FU`。

库来自小米 14 Ultra(同 SM8650)的 Eu 固件 OS3.0.304.0 的 `vendor/lib`,按 `readelf` 依赖 + 字符串里 `dlopen` 的名字算闭包,30 个文件、约 64MB(erofs 压缩后约 25-30MB):

- EGL/GLES:`egl/{libEGL,libGLESv1_CM,libGLESv2}_adreno.so`、`eglSubDriverAndroid.so`
- Vulkan:`hw/vulkan.adreno.so`
- 驱动内部:`libgsl`、`libCB`、`libllvm-{glnext,qgl,qcom}`、`libadreno_utils`、`libkcl`、`libkernelmanager` 等
- gralloc / mapper:`hw/android.hardware.graphics.mapper@4.0-impl-qti-display.so`、`libgralloc*.so`、`vendor.qti.hardware.display.mapper@*/mapperextensions@*`

SELinux 标签不是手写:`label.py` 用 plat + 原厂 vendor 的 `file_contexts` 为 `/vendor/lib/<相对路径>` 现算(规则里本来就写了 `lib(64)?`),并逐个和原厂 64 位同名文件的实际标签核对过,30 个全一致(`same_process_hal_file` / `vendor_hal_file`)。

## 改动清单

- `system/etc/vendor-lib32/**`(30 个文件 + `egl`、`hw` 目录,0644/0755 root:root)
- `system/etc/init/vendor-lib32.rc`

## 输入

| 变量 | 说明 |
|---|---|
| `XIAOMI_LIB32_DIR` | 目录,结构同 `/vendor/lib`,内容与 `manifest.sha256` 逐文件一致(多一个少一个、sha 不对都停)。**不进仓库**,默认 `private/xiaomi-vendor-lib32` |
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像:核对没有同名文件,并取 `vendor_file_contexts` 算标签 |

`manifest.sha256` 是文件名 + sha256 清单(进仓库)。

## 依赖和顺序

无。单独装对 64 位完全没有影响(overlay 里只有 32 位库)。

## 适用范围和换底包注意

- 换原厂 vendor 后:如果新 vendor 的 `lib/` 里已经有了同名 32 位库,构建会停下(说明这个模块不再适用)。
- **版本混搭**:设备 64 位 Adreno 是 `V@0762.28`,这里的 32 位是 `V@0762.4`(小米 OS2.0.213 和 OS3.0.304 的 32 位都是 0762.4,OS1.0.24 是 0744.1)。小米自己的固件也是 32 位 0762.4 配 64 位 0762.30/0762.36,用户态组合可行;与设备内核的 KGSL 是否兼容没验证。
- 如果 overlay 挂载失败,`dmesg | grep -i overlay`;失败不影响启动,只是没有 32 位 GPU。

## 踩过的坑

- 没有真机验证。要点:overlay 挂在自己的 lowerdir 路径上(`/vendor/lib`),是预期用法;lowerdir 左边优先,所以 `system/etc/vendor-lib32` 在前。

## 验证

```bash
adb shell ls /vendor/lib/egl /vendor/lib/rfsa/adsp | head
adb shell ls -lZ /vendor/lib/egl/libGLESv2_adreno.so      # same_process_hal_file
adb shell dmesg | grep -i overlay
```
