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

## 保留 GSI 版本(`ID_KEEP_GSI_OS_VERSION=1`)

当底包比原厂固件新(例:原厂 ZUI 是 Android 15,底包是 Pixel 官方 **CP3A.260905.009 Android 17 / API 37**)时,"整条指纹从原厂现取" 会把系统版本谎报成 Android 15。在 `conf.d/identity.conf` 里设 `ID_KEEP_GSI_OS_VERSION=1`,`apply.sh` 改走 `gsi_overlay.py`:

- **不读原厂镜像**(不需要 `STOCK_SYSTEM_IMG`),改从 **GSI 自带** 的 `system/build.prop` 读指纹。
- 只重写指纹里的机型身份段:`BRAND/PRODUCT/DEVICE:...` 冒号前那段换成 `ID_BRAND/ID_NAME/ID_DEVICE`(= `Lenovo/TB321FU/TB321FU`),冒号后的版本段 `:<release>/<id>/<incremental>:<type>/<tags>` 原样保留 GSI 的。
- 产出同样的 7 个指纹变体(值一致),但**不**写 `ro.build.version.*`、`ro.build.id`、`ro.build.version.security_patch`、`ro.build.tags/type/flavor/description` —— 这些全部保留 GSI 自带的 Android 17 值。
- `ro.build.flavor` / `ro.build.description` 里的机型代号由 `001.product-fields` 把开头的 `tangorpro-user` 换成 `TB321FU-user`(版本串照旧保留 A17),两部分配合得到 "机型是 Lenovo、系统是 Android 17" 的一致身份。

结果:`ro.build.fingerprint = Lenovo/TB321FU/TB321FU:17/CP3A.260905.009/<incremental>:user/release-keys`,`ro.build.version.release=17`、`sdk=37`、`security_patch` 为 GSI 自带的 2026-09 级别 —— 机型还原但不谎报安卓版本(CP3A 这条线的明确要求)。

默认 `ID_KEEP_GSI_OS_VERSION=0`(不设即 0),走上面的 "原厂现取" 路径,ap3a/bp1a 行为不变。

## 改动清单

- 改 `system/build.prop`(缺的 key 会追加)、`system/product/etc/build.prop`、`system/system_ext/etc/build.prop`:上面列的属性

## 输入

| 变量(`device.conf` / `conf.d/identity.conf`) | 说明 |
|---|---|
| `ID_KEEP_GSI_OS_VERSION` | 可选,默认 0。=1 时保留 GSI 自带安卓版本、只换机型身份段(见上节),此时不需要 `STOCK_SYSTEM_IMG` |
| `STOCK_SYSTEM_IMG` | `ID_KEEP_GSI_OS_VERSION=0` 时必须。原厂 system 镜像(从 9008 包的 super 切出来),读指纹 |
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
