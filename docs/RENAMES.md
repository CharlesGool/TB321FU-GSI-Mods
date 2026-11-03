# 补丁改名对照

最初是 `mods/<组>/<模块>/`(2026-10-31 之前)。之后改成 `patches/` 一补丁一文件夹,再把修同一件事 / 关联太紧的合成一个补丁,内部部分放在 `parts/NNN.<部分>/`(2026-11-01)。旧版本的 `MODULES.txt`、`releases/` 里的报告、`doc/` 的研究笔记用的是左边的名字。

| 最初(mods/) | 现在 |
|---|---|
| `art-cache/stale-boot-image` | `stale-boot-image` |
| `backup/app-backup` | `app-backup` |
| `battery/bypass-charging` | `battery` 的部分 `parts/005.bypass-charging/` |
| `battery/charge-limit` | `battery` 的部分 `parts/004.charge-limit/` |
| `battery/charge-protection` | `battery` 的部分 `parts/003.charge-protection/` |
| `battery/health-report` | `battery` 的部分 `parts/002.health-report/` |
| `battery/node-access` | `battery` 的部分 `parts/001.node-access/` |
| `bluetooth/a2dp-offload-policy` | `bluetooth-fix` 的部分 `parts/002.a2dp-offload-policy/` |
| `bluetooth/profile-props` | `bluetooth-fix` 的部分 `parts/001.profile-props/` |
| `bluetooth/sco-ahal-patch` | `bluetooth-fix` 的部分 `parts/003.sco-call-fix/` |
| `boot/assemble` | `boot-assemble` |
| `debloat/accessibility` | `slim/apps` 的部分 `parts/003.accessibility/` |
| `debloat/camera` | `slim/apps` 的部分 `parts/005.google-camera/` |
| `debloat/google-apps` | `slim/apps` 的部分 `parts/001.google-apps/` |
| `debloat/google-assistant` | `slim/apps` 的部分 `parts/002.google-assistant/` |
| `debloat/kids` | `slim/apps` 的部分 `parts/004.kids/` |
| `debloat/play-auto-install` | `slim/apps` 的部分 `parts/006.play-auto-install/` |
| `diag/boot-camera-log` | `diag-boot-camera-log` |
| `faceunlock/app` | `faceunlock` 的部分 `parts/002.app/` |
| `faceunlock/services-hooks` | `faceunlock` 的部分 `parts/001.services-hooks/` |
| `faceunlock/settings-overlay` | `faceunlock` 的部分 `parts/003.settings-entry/` |
| `font/custom-font` | `custom-font` 的部分 `parts/001.hook/` |
| `font/font-control` | `custom-font` 的部分 `parts/002.control/` |
| `game/auto-dnd` | `game-mode` 的部分 `parts/003.auto-dnd/` |
| `game/foreground-trigger` | `game-mode` 的部分 `parts/001.foreground-trigger/` |
| `game/kiosk-lock` | `game-mode` 的部分 `parts/002.kiosk-lock/` |
| `hardening/enforce-at-init` | `selinux/enforce-at-init` |
| `hardening/kernel-enforcing` | `selinux/kernel-enforcing` |
| `hardening/partition-verified` | `gsi-hide` 的部分 `parts/001.partition-verified/` |
| `hardening/qemu-prop-label` | `gsi-hide` 的部分 `parts/002.qemu-prop-label/` |
| `hardening/rw-system-tmpfs` | `rw-system-tmpfs` |
| `hardening/shell-logcat` | `selinux/shell-logcat` |
| `hotspot/entry-quicksettings` | `hotspot-qs-tile` |
| `hotspot/entry-settings` | `hotspot-settings-entry` |
| `identity/build-fingerprint` | `identity` 的部分 `parts/002.build-fingerprint/` |
| `identity/debug-off` | `debug-off` |
| `identity/kernel-builder-string` | `kernel-builder-string` |
| `identity/product-fields` | `identity` 的部分 `parts/001.product-fields/` |
| `identity/version-label` | `identity` 的部分 `parts/003.version-label/` |
| `leftovers/mystic-boot-logcat` | `slim/gsi-traces` 的部分 `parts/002.mystic-boot-logcat/` |
| `leftovers/mystic-vendor-overlays` | `slim/gsi-traces` 的部分 `parts/001.mystic-vendor-overlays/` |
| `leftovers/old-vndk` | `slim/unused-files` 的部分 `parts/001.old-vndk/` |
| `leftovers/phh-keylayouts` | `slim/gsi-traces` 的部分 `parts/003.phh-keylayouts/` |
| `leftovers/phh-prop-handlers` | `slim/gsi-traces` 的部分 `parts/005.phh-prop-handlers/` |
| `leftovers/phh-remotectl` | `slim/gsi-traces` 的部分 `parts/004.phh-remotectl/` |
| `leftovers/unused-ambient-music` | `slim/unused-files` 的部分 `parts/003.ambient-music/` |
| `leftovers/unused-offline-speech` | `slim/offline-speech` |
| `leftovers/unused-tts-voices` | `slim/unused-files` 的部分 `parts/002.tts-voices/` |
| `navbar/control` | `navbar-hide` 的部分 `parts/004.control/` |
| `navbar/overlay-framework` | `navbar-hide` 的部分 `parts/001.overlay-framework/` |
| `navbar/overlay-launcher` | `navbar-hide` 的部分 `parts/003.overlay-launcher/` |
| `navbar/overlay-systemui` | `navbar-hide` 的部分 `parts/002.overlay-systemui/` |
| `navbar/keys` | `navbar-hide` 补丁里的 `keys/`(overlay 签名用) |
| `net/speed-control` | `statusbar-netspeed` 的部分 `parts/002.control/` |
| `net/statusbar-speed` | `statusbar-netspeed` 的部分 `parts/001.display/` |
| `omk/app-spoof` | `spoof/app-spoof` |
| `omk/core` | `herald-core`(2026-11-01 改名,中途短暂叫过 `rootless-core`,运行时标识 omk→herald 全换;并把具体能力拆出去:keymint 引擎 / 指纹 / keybox / RKP 命令 → `attestation-fix`;`heraldctl wifi` / `hotspot` 命令 → `hotspot-control` 的部分 `parts/004.control/`) |
| `omk/default-profile` | `spoof/default-profile` |
| `omk/global-pif` | `spoof/global-pif` |
| `omk/readonly-shell` | `herald-readonly-shell` |
| `omk/zygisk-timing-probe` | `herald-zygisk-timing-probe` |
| `overlay-cache/idmap-reset` | `overlay-idmap-reset` |
| `perf/cpu-freq` | `perf` 的部分 `parts/002.cpu-freq/` |
| `perf/game-boost` | `perf-game-boost` |
| `perf/gpu-freq` | `perf` 的部分 `parts/003.gpu-freq/` |
| `perf/node-access` | `perf` 的部分 `parts/001.node-access/` |
| `perf/profiles` | `perf` 的部分 `parts/004.profiles/` |
| `perf/thermal-readout` | `perf` 的部分 `parts/005.thermal-readout/` |
| `pixel-cleanup/baseband` | `slim/pixel-hardware` 的部分 `parts/008.baseband/` |
| `pixel-cleanup/cast-display` | `slim/pixel-hardware` 的部分 `parts/002.cast-display/` |
| `pixel-cleanup/dcservice-seapp` | `slim/pixel-hardware` 的部分 `parts/009.dcservice-seapp/` |
| `pixel-cleanup/dock-hub` | `slim/pixel-hardware` 的部分 `parts/001.dock-hub/` |
| `pixel-cleanup/hbm-uv` | `slim/pixel-hardware` 的部分 `parts/007.hbm-uv/` |
| `pixel-cleanup/nfc` | `slim/pixel-hardware` 的部分 `parts/010.nfc/` |
| `pixel-cleanup/retail-demo` | `slim/pixel-hardware` 的部分 `parts/003.retail-demo/` |
| `pixel-cleanup/side-fingerprint` | `slim/pixel-hardware` 的部分 `parts/005.side-fingerprint/` |
| `pixel-cleanup/tensor-services` | `slim/pixel-hardware` 的部分 `parts/004.tensor-services/` |
| `pixel-cleanup/uwb` | `slim/pixel-hardware` 的部分 `parts/006.uwb/` |
| `popup-fix/build-consistency-dialog` | `build-consistency-dialog-fix` |
| `privacy/devopts-hide` | `devopts-hide` 的部分 `parts/001.hook/` |
| `privacy/hide-control` | `devopts-hide` 的部分 `parts/002.control/` |
| `screen/adaptive-refresh` | `refresh-rate` 的部分 `parts/003.adaptive/` |
| `screen/auto-brightness` | `brightness/auto-brightness-fix` 的部分 `parts/001.auto-brightness/` |
| `screen/brightness-curve` | `brightness/auto-brightness-fix` 的部分 `parts/003.brightness-curve/` |
| `screen/brightness-debounce` | `brightness/auto-brightness-fix` 的部分 `parts/004.brightness-debounce/` |
| `screen/dock-rotation-fix` | `rotation-fix` 的部分 `parts/002.dock-rotation-fix/` |
| `screen/hbm-unlimited` | `brightness/hbm-unlimited` |
| `screen/min-brightness` | `brightness/auto-brightness-fix` 的部分 `parts/002.min-brightness/` |
| `screen/refresh-rate` | `refresh-rate` 的部分 `parts/002.control/` |
| `screen/rotation-reverse-fix` | `rotation-fix` 的部分 `parts/001.rotation-reverse-fix/` |
| `screen/sf-timers` | `refresh-rate` 的部分 `parts/001.sf-timers/`,后改名 `parts/001.adaptive-refresh-fix/` |
| `tango/core` | `tango` 的部分 `parts/001.core/` |
| `tango/kernel-module` | `tango` 的部分 `parts/003.kernel-module/` |
| `tango/sepolicy` | `tango` 的部分 `parts/002.sepolicy/` |
| `tango/vendor-lib32` | `tango` 的部分 `parts/004.vendor-lib32/` |
| `tango/zygote32` | `tango` 的部分 `parts/005.zygote32/` |
| `vendor-compat/qti-enhanced-framework` | `qti-enhanced-framework` |
| `wifi/6ghz-hotspot` | `hotspot-6ghz` |
| `wifi/apex-assemble` | `hotspot-control` 的部分 `parts/003.apex-assemble/` |
| `wifi/country-code` | `hotspot-control` 的部分 `parts/001.country-code/` |
| `wifi/hotspot-overrides` | `hotspot-control` 的部分 `parts/002.hotspot-custom/` |
| `zui_camera/app` | `zuicamera` 的部分 `parts/001.app/` |
| `zui_camera/aux-camera-list` | `zuicamera` 的部分 `parts/002.aux-camera-list/` |
| `zui_camera/camera-id-check` | `zuicamera` 的部分 `parts/004.camera-id-check/` |
| `zui_camera/hal-client-props` | `zuicamera` 的部分 `parts/003.hal-client-props/` |
| `zui_camera/hide-unsupported` | `zuicamera` 的部分 `parts/006.hide-unsupported/` |
| `zui_camera/real-device-id` | `zuicamera` 的部分 `parts/005.real-device-id/` |

## 2026-11-01:按用途分到 required/ 和 optional/

补丁名(= 路径)前面加了分类:`required/general/`(必须打·通用修复)、`required/gsi-specific/`(必须打·特定底包限定;后来把 device 里的大部分挪回了 general)、`optional/`(可选)。之后又加了 `debug/`(调试用,默认不打),并把 `selinux/shell-logcat` 等 5 个挪进去。
选补丁时可以继续写短名(`battery`、`slim`、`brightness/hbm-unlimited`),按末尾几段匹配;`patch.conf` 的 `REQUIRES` 等和 `device.conf` 的 `MODS` 里要写全名。

| 原名 | 现名 |
|---|---|
| `app-backup` | `optional/app-backup` |
| `attestation-engine` | `optional/attestation-engine` |
| `battery` | `optional/battery` |
| `brightness/hbm-unlimited` | `optional/brightness/hbm-unlimited` |
| `custom-font` | `optional/custom-font` |
| `devopts-hide` | `optional/devopts-hide` |
| `diag-boot-camera-log` | `debug/diag-boot-camera-log` |
| `faceunlock` | `optional/faceunlock` |
| `game-mode` | `optional/game-mode` |
| `herald-readonly-shell` | `debug/herald-readonly-shell` |
| `herald-zygisk-fork-observer` | `debug/herald-zygisk-fork-observer` |
| `herald-zygisk-timing-probe` | `debug/herald-zygisk-timing-probe` |
| `navbar-hide` | `optional/navbar-hide` |
| `overlay-idmap-reset` | `optional/overlay-idmap-reset` |
| `perf` | `optional/perf` |
| `perf-game-boost` | `optional/perf-game-boost` |
| `slim/offline-speech` | `optional/slim/offline-speech` |
| `spoof/app-spoof` | `optional/spoof/app-spoof` |
| `spoof/default-profile` | `optional/spoof/default-profile` |
| `spoof/global-pif` | `optional/spoof/global-pif` |
| `statusbar-netspeed` | `optional/statusbar-netspeed` |
| `tango` | `optional/tango` |
| `bluetooth-fix` | `required/general/hardware-fix/bluetooth-fix` |
| `brightness/auto-brightness-fix` | `required/general/brightness/auto-brightness-fix` |
| `hotspot-6ghz` | `required/general/hardware-fix/hotspot-6ghz` |
| `hotspot-control` | `required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/hotspot-control` |
| `hotspot-qs-tile` | `required/gsi-specific/hotspot-ui`(2026-11-01 和 settings-entry 合并,成 `parts/002.qs-tile`) |
| `hotspot-settings-entry` | `required/gsi-specific/hotspot-ui`(`parts/001.settings-entry`) |
| `identity` | `required/general/bug-fix/identity` |
| `qti-enhanced-framework` | `required/general/bug-fix/qti-enhanced-framework` |
| `refresh-rate` | `required/general/hardware-fix/refresh-rate` |
| `rotation-fix` | `required/gsi-specific/rotation-fix` |
| `slim/pixel-hardware` | `required/gsi-specific/slim/pixel-hardware`(先放过 general,又挪到 gsi-specific:这些组件只有 Pixel Tablet 的 GSI 才带) |
| `zuicamera` | `required/general/hardware-fix/zuicamera` |
| `boot-assemble` | `required/general/boot-kernel/boot-assemble` |
| `build-consistency-dialog-fix` | `required/general/bug-fix/build-consistency-dialog-fix` |
| `debug-off` | `required/general/bug-fix/debug-off` |
| `gsi-hide` | `required/general/bug-fix/gsi-hide` |
| `herald-core` | `required/general/herald-core` |
| `kernel-builder-string` | `required/general/boot-kernel/kernel-builder-string` |
| `rw-system-tmpfs` | `required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/rw-system-tmpfs` |
| `selinux/fix` | `required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/selinux/fix` |
| `selinux/shell-logcat` | `debug/shell-logcat` |
| `slim/apps` | `required/general/slim/apps` |
| `slim/gsi-traces` | `required/tangorpro/tangorpro_ap3a.241005.015/slim/gsi-traces` |
| `slim/unused-files` | `required/general/slim/unused-files` |
| `stale-boot-image` | `required/general/boot-kernel/stale-boot-image` |

## 精简合并(2026-11-01)

`slim/apps`、`slim/unused-files`、`slim/pixel-hardware` 合并成 `required/general/slim/targets`:按底包唯一 ID(`<产品>_<构建号>_<增量号>`)挑清单,清单在补丁的 `lists/<common|前缀>/`,支持通配符。

| 原 | 现 |
|---|---|
| `required/general/slim/apps/parts/NNN.x` | `…/targets/lists/optional/common/{google-apps,google-assistant,accessibility}.list`;`kids`、`google-camera`、`play-auto-install` → `…/lists/required/common/` |
| `required/general/slim/unused-files/parts/002.tts-voices`、`003.ambient-music` | `tts-voices` → `…/lists/optional/common/`,`ambient-music` → `…/lists/required/common/` |
| `required/general/slim/unused-files/parts/001.old-vndk` | `…/targets/parts/001.old-vndk` |
| `required/gsi-specific/slim/pixel-hardware/parts/NNN.x`(9 项清单) | `…/targets/lists/required/tangorpro/x.list` |
| `required/gsi-specific/slim/pixel-hardware/parts/009.dcservice-seapp` | `required/gsi-specific/dcservice-seapp`(不是精简,独立补丁) |

## 自动亮度修复去掉多余的文件夹(2026-11-01)

| 原 | 现 |
|---|---|
| `required/general/brightness/auto-brightness-fix` | `required/general/hardware-fix/auto-brightness-fix` |

## 加 -fix 后缀(2026-11-01)

| 原 | 现 |
|---|---|
| `required/gsi-specific/hotspot-ui` | `required/gsi-specific/hotspot-ui-fix` |
| `required/gsi-specific/dcservice-seapp` | `required/gsi-specific/dcservice-seapp-fix`(并且只对底包 ID `tangorpro_ap3a.241005.015*` 生效) |

## gsi-specific 改成按底包 ID 前缀分文件夹(2026-11-01)

特定底包的补丁文件夹名就是底包 ID 的前缀,构建时只有底包 ID(取自指纹)命中才跑(`toolkit/lib/runmods.sh` 的 `scope_ok`)。

| 原 | 现 |
|---|---|
| `required/gsi-specific/rotation-fix` | `required/tangorpro/rotation-fix`(所有 Pixel Tablet 的 GSI) |
| `required/gsi-specific/hotspot-ui-fix` | `required/tangorpro/hotspot-ui-fix`(所有 Pixel Tablet 的 GSI) |
| `required/gsi-specific/dcservice-seapp-fix` | `required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix`(只有这一版) |

## required/general 按类分文件夹(2026-11-01)

| 类 | 补丁(原来直接在 `required/general/` 下) |
|---|---|
| `hardware-fix/`(硬件功能修复) | `auto-brightness-fix`、`refresh-rate`、`bluetooth-fix`、`zuicamera`、`hotspot-6ghz`、`hotspot-control` |
| `bug-fix/`(漏洞修复:系统 build、SELinux、GSI 制作遗留、身份) | `identity`、`gsi-hide`、`debug-off`、`selinux`、`rw-system-tmpfs`、`build-consistency-dialog-fix`、`qti-enhanced-framework` |
| `boot-kernel/`(boot / kernel 的修改修复) | `stale-boot-image`、`kernel-builder-string`、`boot-assemble` |
| `slim/`(精简) | 不变(`slim/targets`、`slim/gsi-traces`) |
| `herald-core` | 不变,仍直接在 `required/general/` 下 |

补丁全名统一加了一层(如 `required/general/refresh-rate` → `required/general/hardware-fix/refresh-rate`);选择规则的短名(`refresh-rate`)不变,类名(`hardware-fix`)可以一次选一批。

## 精简清单放进各补丁自己的文件夹(2026-11-01)

`slim/targets` 拆掉:精简脚本通用(`toolkit/lib/removelist.sh` 的 `slim_apply`),清单跟着各补丁走。适用范围由补丁所在文件夹决定,不再有 `SLIM_OPTIONAL` 和范围目录。

| 原 `slim/targets` | 现 |
|---|---|
| `lists/required/common/{play-auto-install,ambient-music,google-camera,kids}` | `required/tangorpro/tangorpro_ap3a.241005.015/slim/pixel-leftovers/lists/` |
| `lists/required/tangorpro/*`(9 份) | `required/tangorpro/tangorpro_ap3a.241005.015/slim/pixel-hardware/lists/` |
| `lists/optional/common/{google-apps,google-assistant,tts-voices}` | `optional/slim/google-apps/lists/` |
| `lists/optional/common/accessibility` | `optional/slim/accessibility/lists/` |
| `parts/001.old-vndk` | `required/general/slim/old-vndk` |

## 按"任意版本 / 特定版本"重分(2026-11-01)

`required/general/` 只放任何 Pixel、任意版本的 GSI 都能用的补丁;绑了某一版 GSI(Mystic / phh 内容、A15 的 Wi-Fi APEX smali)的放进 `required/tangorpro/tangorpro_ap3a.241005.015/`,里面按 `bug-fix/`、`hardware-fix/`、`slim/` 分类。别的版本的 GSI 复制一份到自己的版本文件夹再改。

| 原 | 现 |
|---|---|
| `required/general/slim/{gsi-traces,pixel-leftovers}`、`required/tangorpro/slim/pixel-hardware` | `required/tangorpro/tangorpro_ap3a.241005.015/slim/…` |
| `required/general/bug-fix/selinux`、`rw-system-tmpfs` | `required/tangorpro/tangorpro_ap3a.241005.015/bug-fix/…` |
| `required/tangorpro/tangorpro_ap3a.241005.015/dcservice-seapp-fix` | `…/tangorpro_ap3a.241005.015/bug-fix/dcservice-seapp-fix` |
| `required/general/hardware-fix/hotspot-control` | `required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/hotspot-control` |

## 热点和刷新率拆分(2026-11-01)

| 原 | 现 |
|---|---|
| `hardware-fix/hotspot-6ghz`(能力位 + 信道列表 + `herald_6g_*` 控制) | `optional/hotspot-6ghz-unlock`(只解锁);`herald_6g_*` 控制挪进 `hotspot-control/parts/003.6ghz-control`(后面的部分顺延:`004.apex-assemble`、`005.control`) |
| `hardware-fix/refresh-rate` 的 `001.adaptive-refresh-fix` | `required/general/hardware-fix/adaptive-refresh-fix`(必须打) |
| `hardware-fix/refresh-rate` 的 `002.control` | `optional/refresh-control`(可选) |

`hotspot-control` 的 `01-SoftApManager-overrides.diff` 把新增的 `heraldApplyApOverrides` 挪到了回编后的排序位置(`handleStartSoftApFailure` 之后、`isBridgeRequired` 之前);omk→herald 改名后字母序变了,原来的位置会让 apex-assemble 的等价核对失败。

## 联想相机改为可选(2026-11-01)

| 旧名 | 新名 |
|---|---|
| `required/general/hardware-fix/zuicamera` | `optional/zuicamera`(默认不打) |
| `optional/zuicamera` 的部分 `hal-client-props` | 已删除(固定设 HAL 客户端属性会影响其他相机应用) |
| `required/general/bug-fix/qti-enhanced-framework` | `required/general/hardware-fix/macro-camera-fix`(微距相机修复:效果只有微距暴露,真机验证无副作用) |

## 热点控制拆分、产物命名(2026-11-01)

| 旧 | 新 |
|---|---|
| `required/tangorpro/tangorpro_ap3a.241005.015/hardware-fix/hotspot-control` 的 `001.country-code`、`003.6ghz-control` | 必选 `…/hardware-fix/6ghz-fix`(`001.country-code`、`002.band-fix`;频段固定 6GHz,信道/带宽不再固定) |
| 同上的 `004.apex-assemble` | 必选 `…/hardware-fix/wifi-apex-assemble`(单独补丁) |
| 同上的 `002.hotspot-custom`、`005.control` | 可选 `optional/hotspot-control`(`001.hotspot-custom`、`002.control`) |
| 产物 `Pixel-tangorpro-15_TB321FU_V103-PIF_erofs_raw_Signed.img`、`releases/V103-PIF/` | `pixelos_tangorpro_ap3a.241005.015_v104[_optional][_debug]`(镜像和 releases 目录);刷机目录标准的 `VN-PIF` 不变 |

## 相机三选一与 Google 精简拆分(V105)

| 旧 | 新 |
|---|---|
| `optional/zuicamera` | `required/general/camera/zuicamera`(由 `CAMERA=zui` 选中) |
| `optional/pixel-camera` | `required/general/camera/pixel-camera`(`CAMERA=pixel`,默认) |
| `optional/slim/google-apps` 的 `google-apps.list` 里 YouTube 全家、Meet、Home、Wellbeing、Health、Tips、ARCore、DevicePolicy、壁纸、位置记录 | `required/tangorpro/tangorpro_ap3a.241005.015/slim/google-extras` |

## 密钥认证改必选、合并、改名(2026-11-01)

| 旧 | 新 |
|---|---|
| `optional/attestation-engine` | `required/general/attestation-fix`(改必选;`spoof/default-profile` 并入,不再单独是一个补丁) |
| `optional/spoof/default-profile` | 已删除,逻辑并入上面的补丁(`apply.sh` 第 4 段) |
