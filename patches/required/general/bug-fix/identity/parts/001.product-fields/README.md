# identity/product-fields — 机型字段

## 做什么

把 `ro.product.{system,product,system_ext}.{brand,device,manufacturer,model,name}` 改成 Lenovo / TB321FU。很多 App 和设置界面直接读这几个字段。

## 原理

GSI 的 system 分区这几个字段是 `google / generic / mainline`,product 和 system_ext 是 `google / tangorpro / Pixel Tablet`。逐分区把这五个字段改成 `device.conf` 里的值。顺带改 system/build.prop 里带机型代号的几项:

- `ro.build.flavor` → `<ID_DEVICE>-user`
- `ro.build.product` → `<ID_DEVICE>`
- `ro.build.description` 开头的 `<GSI_CODENAME>-user` → `<ID_DEVICE>-user`(只换开头的机型代号,后面的版本串不动)
- product 分区的 `ro.quick_start.device_id`(快速设置/设备迁移用的设备 ID)→ `<ID_DEVICE>`

`flavor` 和 `description` 只在开头是 `<GSI_CODENAME>-user` 时才换(只换开头的机型代号,后面的版本串不动);如果 `build-fingerprint` 先跑过,它们已经是原厂值,这里就不碰(打一行提示)。所以这个模块和 `build-fingerprint` 谁先谁后、单开哪个,结果都合理。

## 改动清单

- 改 `system/build.prop`:`ro.product.system.*`、`ro.build.flavor`、`ro.build.product`、`ro.build.description`
- 改 `system/product/etc/build.prop`:`ro.product.product.*`、`ro.quick_start.device_id`(有才改)
- 改 `system/system_ext/etc/build.prop`:`ro.product.system_ext.*`

## 依赖和顺序

无依赖。和 `build-fingerprint` 谁先谁后都行,见组 README。

## 输入(`conf.d/identity.conf`)

`ID_BRAND` `ID_DEVICE` `ID_MANUFACTURER` `ID_MODEL` `ID_NAME`,以及 `GSI_CODENAME`(底包原机代号,如 `tangorpro`)。

## 换底包注意

- 五个 `ro.product.<分区>.*` 字段少任何一个就构建失败(说明底包的 build.prop 结构变了)。
- Mystic 这版底包的 product/build.prop 里**没有** `ro.quick_start.device_id`,所以这一项现在是空操作(脚本会打一行"跳过")。别的底包有就会改。
- `ro.build.flavor` / `ro.build.description` 不是以 `<GSI_CODENAME>-user` 开头时只提示、不失败、不改(通常是 `build-fingerprint` 先跑过)。

## 验证

```bash
adb shell getprop ro.product.system.model     # TB321FU
adb shell getprop ro.product.product.brand    # Lenovo
adb shell getprop ro.build.product            # TB321FU
```
