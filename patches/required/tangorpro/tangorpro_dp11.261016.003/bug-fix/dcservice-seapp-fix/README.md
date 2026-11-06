# dcservice-seapp-fix — 设备连接服务的 SELinux 域

## 做什么

从 `system_ext/etc/selinux/system_ext_seapp_contexts` 里删掉两行 `domain=dcservice_app` 的规则,让设备连接服务(`com.google.android.apps.pixel.dcservice` 和 `.ui`)落到通用的 priv_app 域。

## 原理

seapp_contexts 把这两个包指到了 `dcservice_app` 域。但 `dcservice_app` 这个 SELinux 类型**只在 Pixel 的 vendor sepolicy 里有**,TB321FU 的 vendor 里没有 → zygote 给进程 `setcontext` 失败,每 10 秒 SIGABRT 一次。删掉这两行后,这两个包按 `isPrivApp=true` 的默认规则落到 `priv_app`,不再崩。

两行的内容:

```
user=_app isPrivApp=true name=com.google.android.apps.pixel.dcservice domain=dcservice_app type=privapp_data_file levelFrom=user
user=_app isPrivApp=true name=com.google.android.apps.pixel.dcservice.ui domain=dcservice_app type=privapp_data_file levelFrom=user
```

`fix_seapp.py` 原地改写文件(不新建),保留属主、权限和 SELinux 标签。这是改 system_ext 里的文本文件,不碰 sepolicy 本身,也不改 `plat_sepolicy.cil`,所以不会触发开机重编策略。

这个模块**不删应用**(设备连接服务本身留着),只修规则。

## 改动清单

- 改 `system/system_ext/etc/selinux/system_ext_seapp_contexts`:删两行

## 输入

无。

## 适用范围

只针对底包 ID 以 `tangorpro_dp11.261016.003` 开头的那一版 Pixel Tablet GSI(Android 15,CP3A.260905.009);别的版本的 Tablet GSI 没有这个问题。适用范围由文件夹表达:补丁放在 `required/tangorpro/tangorpro_dp11.261016.003/` 下,构建时底包 ID 不命中就整个跳过(日志写"跳过 … 不在适用范围")。底包 ID 取自构建开头记下的指纹,见 `toolkit/lib/removelist.sh` 的 `base_id`。

## 依赖和顺序

不依赖别的补丁;和精简补丁互不影响。只有带 `dcservice_app` 规则的底包(Pixel Tablet 的 GSI)才会动文件,别的底包跳过。

## 换底包注意

- 底包 ID 不是 `tangorpro_dp11.261016.003*` → 整个补丁被构建跳过,不改任何东西。
- 底包里没有 `domain=dcservice_app`→ 模块 log "跳过",不失败。
- 底包有但数量不是 2(`fix_seapp.py` 里的 `EXPECT = 2`)→ 停下来报错,让人确认再改数字。
- 删完会再核对一遍文件里已经没有 `dcservice_app`。

## 验证

```bash
adb logcat -b crash -d | grep -i dcservice          # 不再反复崩
adb shell ps -AZ | grep -i dcservice                # 域是 u:r:priv_app:s0,不是 dcservice_app
```
