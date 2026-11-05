#!/usr/bin/env bash
# faceunlock/app:放 FaceUnlock.apk(priv-app)和 4 份权限 / 白名单 / 默认权限 xml。
# 不动 services.jar(那是 faceunlock/services-hooks),也不放设置入口 overlay(faceunlock/settings-entry)。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

PKG=com.android.faceunlock

# ---- 前提 ----
need_file priv-app
need_file etc/permissions
need_file etc/sysconfig
need_file product/etc/default-permissions
for f in FaceUnlock.apk \
         privapp_whitelist_${PKG}.xml android.hardware.biometrics.face.xml \
         hiddenapi-whitelist-${PKG}.xml default_permissions_${PKG}.xml; do
    [[ -f $MOD/files/$f ]] || die "缺预编译件 $MOD/files/$f"
done

# ---- App:目录要自己建并定标签(不然是 unlabeled,V29 HeraldControl 目录踩过)----
put_dir "priv-app/FaceUnlock" 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/FaceUnlock.apk"                   priv-app/FaceUnlock/FaceUnlock.apk                               0644 0:0 u:object_r:system_file:s0

# ---- 4 份 xml ----
put "$MOD/files/privapp_whitelist_${PKG}.xml"     etc/permissions/privapp_whitelist_${PKG}.xml                     0644 0:0 u:object_r:system_file:s0
put "$MOD/files/android.hardware.biometrics.face.xml" etc/permissions/android.hardware.biometrics.face.xml         0644 0:0 u:object_r:system_file:s0
put "$MOD/files/hiddenapi-whitelist-${PKG}.xml"   etc/sysconfig/hiddenapi-whitelist-${PKG}.xml                     0644 0:0 u:object_r:system_file:s0
put "$MOD/files/default_permissions_${PKG}.xml"   product/etc/default-permissions/default_permissions_${PKG}.xml   0644 0:0 u:object_r:system_file:s0

log "完成:FaceUnlock priv-app + 4 份权限 xml"
