# 合并 spoof/app-spoof 要做的事

用户要求"先不实装",所以改 attestation-fix、spoof/global-pif、device.conf 的部分都放在这里,没动原文件。三份 diff 都是对 V81 时的文件做的(`patch -p1 --dry-run` 在仓库根下通过)。

## 1. 打补丁(仓库根目录)

```bash
patch -p1 < patches/optional/spoof/app-spoof/pending/herald-global-pif.sh.diff
patch -p1 < patches/optional/spoof/app-spoof/pending/herald-start.sh.diff
patch -p1 < patches/optional/spoof/app-spoof/pending/heraldctl.diff
```

| 文件 | 改了什么 |
|---|---|
| `patches/optional/spoof/global-pif/files/herald-global-pif.sh` | 开机先删 `/data/system/imitation.conf`;伪装开着时按模式分支:装了 app-spoof 且 `spoof_mode` 不是 global → 写配置文件(名单 + 15 个字段)、chcon、**不 resetprop**,退出;否则照旧 resetprop 15 个属性 |
| `patches/required/general/attestation-fix/files/00-attestation.sh(原 herald-start.sh 里的这部分,拆分后搬到了这里;diff 的行号已过时)` | 新增 `herald_app_spoof_on`、`herald_cfg_secpatch`、`herald_spoof_patch_sync`;`herald_patch_core` 在 app 模式下不调 keymint 同步、config.toml 的 security_patch 固定真机日期、只改 profile(带 all 时 os/vendor/boot 跟 profile);`diag` 多两行(`mode=`、配置文件 `ls -lZ`)。`spoof get/set/disable/patch` 的回包格式不变(app 模式下 patch 回包是 `ok patch <日期> via=app-spoof reboot-required`) |
| `patches/required/general/attestation-fix/files/heraldctl-attestation.sh` | `spoof mode [app|global]`、`spoof apps [list|add|remove <名字>]` 两个子命令(只增),帮助两行 |

不打这三个补丁、只装模块时:钩子在、插件在,但伪装脚本不写配置文件,所以整机行为和 V81 一样(global 模式)。

## 2. device.conf

```
    herald-core
    spoof/global-pif
    spoof/app-spoof                   # 按 App 伪装(默认模式);heraldctl spoofmode app|global 切换
    ...
    stale-boot-image      # ← 从 popup-fix 后面挪到这里:必须排在所有改 framework.jar 的模块后面
```

`stale-boot-image` 现在排在 herald 段前面,而 app-spoof 要 herald-core 在前(装插件)又要在 art-cache 前面,所以 art-cache 要挪到 herald 段之后。它只删过期的 boot image,后面没有别的模块改 jar,挪后没有副作用。

顺带发现(不在本任务范围):`build-consistency-dialog-fix` 和 `faceunlock/services-hooks` 检查顺序用的是 `$BUILD_STATE/ran/framework__stale-boot-image`,实际的标记名是 `art-cache__stale-boot-image`,所以那两个检查永远不会触发。**已修**(2026-10-31 目录整理时统一改成 `mod_ran required/general/boot-kernel/stale-boot-image`)。

## 3. 构建后核对

- `MODULES.txt` 有 `spoof/app-spoof`;镜像里 `framework.jar` 有 `PropImitationHooks`(apply.sh 已自检)、`etc/herald_payload/app-spoof/targets.default`、`plugins/app-spoof.sh`、`heraldctl.d/app-spoof.sh`、`plat_sepolicy.cil` 里有 `imitation_conf_file`。
- 跑 `bash toolkit/test-herald-protocol.sh devices/tb321fu-a15/device.conf`(主机上没有 /system/etc/herald_payload/app-spoof,所以测的是 global 分支,应和合并前一样全部通过)。
