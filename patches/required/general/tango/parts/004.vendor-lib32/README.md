# tango/vendor-lib32

给 `/vendor/lib` 补上 32 位 GPU 和 gralloc 库. 原厂 vendor 的 `lib/` 只有 DSP 库 (`rfsa/adsp`), 没有 32 位 Adreno 驱动; 32 位 app 进程使用 HWUI, 没有 32 位 EGL, GLES 和 Vulkan 就画不出界面.

## 原理

vendor 分区只读且受 AVB 保护, 不能直接加文件. 本部分把库放进 `system/etc/vendor-lib32/`, 在 `post-fs` 用 init 自带的 `mount` 把它和原厂 `/vendor/lib` 叠成只读 overlay, 盖回 `/vendor/lib`:

```text
mount overlay overlay /vendor/lib ro nosuid nodev lowerdir=/system/etc/vendor-lib32:/vendor/lib
```

- lowerdir 左边优先. 两边没有同名文件, 原厂的 `rfsa/` 和 `modules/` 照常可见.
- 不用 `vendor-bind`: 它是单文件替换, 目标必须已存在; 这里是新增整套文件.
- 用 init 的 `mount` 而不是脚本, 不新增 SELinux 域. rc 只在 `ro.product.vendor.device=TB321FU` 时执行.

库取自小米 14 Ultra (同为 SM8650) xiaomi.eu OS3.0.304.0 的 `vendor/lib`, 按 `readelf` 依赖和字符串中 `dlopen` 的库名算出闭包, 共 30 个文件, 约 64 MB:

- EGL 和 GLES: `egl/{libEGL,libGLESv1_CM,libGLESv2}_adreno.so`, `eglSubDriverAndroid.so`
- Vulkan: `hw/vulkan.adreno.so`
- 驱动内部库: `libgsl`, `libCB`, `libllvm-{glnext,qgl,qcom}`, `libadreno_utils`, `libkcl`, `libkernelmanager` 等
- gralloc 和 mapper: `hw/android.hardware.graphics.mapper@4.0-impl-qti-display.so`, `libgralloc*.so`, `vendor.qti.hardware.display.mapper@*`, `mapperextensions@*`

SELinux 标签由 `label.py` 用底包和原厂 vendor 的 `file_contexts` 为 `/vendor/lib/<相对路径>` 计算 (规则本来写的是 `lib(64)?`). 30 个结果都与原厂 64 位同名文件的实际标签一致 (`same_process_hal_file` 或 `vendor_hal_file`).

## 改动清单

- `system/etc/vendor-lib32/**` (30 个文件和 `egl/`, `hw/` 目录)
- `system/etc/init/vendor-lib32.rc`

## 输入

| 变量 | 说明 |
| --- | --- |
| `XIAOMI_LIB32_DIR` | 目录结构同 `/vendor/lib`, 内容**必须**与 `manifest.sha256` 逐文件一致, 多文件, 缺文件或哈希不同都会停止构建. **禁止**进仓库 |
| `STOCK_VENDOR_IMG` | 原厂 vendor 镜像, 用来核对没有同名文件, 并读取 `vendor_file_contexts` |

`manifest.sha256` 只含文件名和 SHA-256.

## 依赖和适用范围

- 没有依赖. overlay 里只有 32 位库, 不影响 64 位进程.
- 换原厂 vendor 后, 新 vendor 的 `lib/` 已有同名 32 位库时构建会停止, 说明本部分不再适用.
- 设备 64 位 Adreno 是 `V@0762.28`, 这里的 32 位是 `V@0762.4`. 小米自己的固件也是 32 位 0762.4 配 64 位 0762.30 或 0762.36; 与设备内核 KGSL 的兼容性没有单独验证.
- overlay 挂载失败不影响开机, 只是没有 32 位 GPU 栈; 用 `dmesg | grep -i overlay` 查原因.

## 验证

```bash
adb shell ls /vendor/lib/egl /vendor/lib/rfsa/adsp | head
adb shell ls -lZ /vendor/lib/egl/libGLESv2_adreno.so      # same_process_hal_file
```
