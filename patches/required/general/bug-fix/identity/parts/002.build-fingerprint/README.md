# identity/build-fingerprint — 指纹和 build 描述符

## 做什么

把系统的指纹换成原厂 ZUI 的(`qti/TB321FU/TB321FU:15/AQ3A.240912.001/...:user/release-keys`),build id、增量号、安全补丁、tags、type、flavor、description 也一起换成原厂的。

## 原理

指纹和描述符**不手写,逐字取自原厂固件**:`apply.sh` 把 `STOCK_SYSTEM_IMG`(可选还有 `STOCK_VENDOR_IMG`)loop 只读挂载,读出 build.prop,`stock_overlay.py` 生成一份 overlay:

- 7 个指纹变体:`ro.build.fingerprint`、`ro.{system,product,vendor,odm,bootimage,system_ext}.build.fingerprint`,值都一样
- `ro.build.id`、`ro.system.build.id`、`ro.build.version.{security_patch,release,release_or_codename,incremental}`、`ro.build.tags`、`ro.system.build.tags`、`ro.build.type`、`ro.build.flavor`、`ro.build.description`
- `ro.vendor.build.security_patch`:优先取原厂 vendor 的,没有就用 system 的安全补丁

然后用 `toolkit/lib/propedit.py overlay` 写进三份 build.prop:已有的 key 就地改;**system/build.prop 用 `--add-missing`**,另两份只改已有的 key(跳过的是 overlay 里它们本来没有的 key)。

为什么 system 要补 key:GSI 的 system/build.prop 常常没有裸的 `ro.build.fingerprint`(运行时由 `ro.product.*` 拼出来)。但原厂 ROW 指纹里的 incremental 槽和 `ro.build.version.incremental` 对不上,拼不出来,必须显式写死。

为什么用原厂 A15 ROW 的指纹:GSI 是 Android 15,原厂 ZUI 17.0.12 的 system 也是 A15,只换系统侧指纹 → system 报 A15,真 vendor/odm 保持原厂 A14,和真机逐字一致。attestation 走的是 bootloader 传的 vbmeta 摘要,和这些 Java 层属性无关。

## 改动清单

- 改 `system/build.prop`(缺的 key 会追加)、`system/product/etc/build.prop`、`system/system_ext/etc/build.prop`:上面列的属性

## 输入

| 变量(`device.conf`) | 说明 |
|---|---|
| `STOCK_SYSTEM_IMG` | 必须。原厂 system 镜像(从 9008 包的 super 切出来),读指纹 |
| `STOCK_VENDOR_IMG` | 可选。读 `ro.vendor.build.security_patch`;不给或文件不存在就用 system 的 |

## 依赖和顺序

无依赖。和 `product-fields` 谁先谁后都行:这个模块总是写原厂值(system/build.prop 缺的 key 会补),`product-fields` 碰到已经是原厂值的 flavor/description 就不动。

## 换底包注意

- 换原厂固件:改 `STOCK_SYSTEM_IMG` 路径即可,指纹自动跟着变。
- 原厂 build.prop 缺 overlay 需要的任何一个 key,`stock_overlay.py` 会报错停下,不会出一个缺字段的镜像。
- 需要宿主机能 `sudo mount -o loop`。
- 换 GSI 底包:三份 build.prop 在就行。

## 验证

```bash
adb shell getprop ro.build.fingerprint        # qti/TB321FU/...ROW...
adb shell getprop ro.vendor.build.fingerprint # 同一条
adb shell getprop ro.build.version.security_patch
```
