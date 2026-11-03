# macro-camera-fix — 微距相机修复:补回原厂 system 里的 ro.vendor.qti.va_aosp.support=1

## 问题

联想相机的微距是 2 号相机。本系统上相机 HAL 只报 0、1 号,可内核开机时明明探测到了微距(2026-10-31 测试机开机日志:`Probe success for kirby_lce_sc202cs_macro slot:2`)。

## 原因

高通 vendor 里有个库 `libqti_vndfwk_detect.so`,函数 `isRunningWithVendorEnhancedFramework()` 的全部逻辑就是读 `ro.vendor.qti.va_aosp.support`(默认 false)。这个属性原厂写在 **system** 的 `build.prop` 里;换成 GSI 后没有了,vendor 就认为自己跑在 GSI 上。

相机 HAL 的 `com.qti.chi.override.so`(`ExtensionModule::GetNumCameras` 一带)按 SoC 选多摄配置:是增强版 system 就用 `camxoverridesettings.txt` 里的 `lanai_pineapple.xml`(原厂行为),否则换成 `lanai_gsi.xml`,后者只暴露主摄和前摄。

## 做法

`system/build.prop` 加 `ro.vendor.qti.va_aosp.support=1`,和原厂一字不差。标签走 `ro.vendor.` 前缀 → `vendor_default_prop`,vendor 进程都能读。

## 影响面(为什么不是只改相机)

vendor 里直接调这个判断的只有:`com.qti.chi.override.so`、`libchifeature2.so`、`libcamxcommonutils.so`(相机)、`lib-rtpsl.so`(IMS 的 RTP)、`libcne.so`(CNE 连接引擎)、`libwqe.so`(Wi-Fi 质量评估)。原厂这些全部在属性 = 1 下运行,= 0 才是偏离原厂的状态。IMS 在这台 Wi-Fi 平板上不用;CNE/WQE 在增强模式下可能会去找高通 system 侧的服务(本系统没有),上真机后要看 Wi-Fi / 热点是否正常。

**真机结果(用户 2026-11-01):** 开着这个补丁,Wi-Fi、热点、蓝牙等都正常,没有发现副作用。对本项目来说实际可见的效果只有一个:相机多出 2 号微距。

不行就构建时 `WITHOUT=macro-camera-fix`,恢复 GSI 模式(相机只有 2 个)。

## 配合

开了这个模块,`zuicamera/hide-unsupported` 就不再从模式栏去掉微距(要排在它前面,它按 `BUILD_STATE` 判断这个模块跑没跑)。

## 验证(cmd.exe)

```bat
adb shell getprop ro.vendor.qti.va_aosp.support
adb shell dumpsys media.camera > cam.txt
findstr /c:"Number of camera devices" cam.txt
```
预期 `1` 和 `Number of camera devices: 3`。再看联想相机模式栏有"微距"、能出画面;Wi-Fi、热点、蓝牙照常。
