#!/usr/bin/env bash
# faceunlock/settings-entry:放设置里「人脸解锁」入口的静态 overlay(目标包 com.android.settings)。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

# ---- 前提 ----
need_file product/overlay
[[ -f $MOD/files/FaceUnlockSettingsOverlay.apk ]] || die "缺预编译件 $MOD/files/FaceUnlockSettingsOverlay.apk"

put "$MOD/files/FaceUnlockSettingsOverlay.apk"    product/overlay/FaceUnlockSettingsOverlay.apk                    0644 0:0 u:object_r:system_file:s0

log "完成:FaceUnlockSettingsOverlay.apk"
