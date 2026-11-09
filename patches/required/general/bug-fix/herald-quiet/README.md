# TB321FU：herald 不再刷 avc 日志

## 问题

herald 是 permissive 域，所有访问照常放行，但每次被策略拒绝的访问仍会记一条 avc。
- 2026-11-09 实测：dmesg 里 504 条 avc，480 条是 herald。
- 主要来源：
  - ush 代跑的 sh、pidof、chmod、ls、rm、settings、dumpsys；
  - broker 每 5 秒一次的 IDLE 检查。
- 几分钟就把 dmesg 冲掉，开机日志和其他真正的问题（比如 vendor 服务的拒绝）都看不到了。

## 改法

apply.sh 用 `cil_append` 把 `herald_quiet.cil` 追加到 plat_sepolicy.cil 末尾(herald-core 那段之后)。

这段内容：
- 定义一个包含所有 type 的属性 `herald_quiet_target`；
- 对 108 个 class 各写一条 `dontaudit herald herald_quiet_target (<class> (all))`。

影响：
- 只影响日志：permissive 本来就全部放行，所以行为不变。
- 只静默 herald 作为 source 的访问。其他域访问 herald 的记录（比如 keystore → herald、system_server → herald）照常保留。
- tb321fu-vibrator 也跑在 herald 域，它的 avc 一起静默。

`plat_sepolicy_and_mapping.sha256` 你们已经是全 0（每次开机由 init 在设备上编译），所以不用重算 precompiled。

## 验证

**编译（已在 test-v2.0 上做过）：** 用 init 同款的 secilc 命令，把设备当前的策略加上本文件编一遍，不加载：
```
adb push herald_quiet.cil test_compile_on_device.sh /data/local/tmp/
adb shell 'ush -c "sh /data/local/tmp/test_compile_on_device.sh"'
#   /system/etc/selinux/plat_sepolicy.cil -> rc=0 size=1547981
#   /data/local/tmp/plat_quiet.cil -> rc=0 size=1591684      （多 44 KB）
```

**刷入后：**
```
adb shell 'ush -c "dmesg"' | grep -c 'scontext=u:r:herald'      # 应为 0
adb shell 'ush -c "dmesg"' | grep -c 'avc:'                       # 只剩非 herald 的
```

## 回退

去掉本补丁重新构建。
