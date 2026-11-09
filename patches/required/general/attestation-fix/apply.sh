# 密钥认证(引擎 + 默认身份):keymint(attestation 引擎)+ inject(ptrace 注入 keystore2)+ resetprop(boot-state)和配置种子。
# 挂在 herald-core 上:启动靠 broker 插件(HERALDP_START),命令靠 broker / heraldctl 插件。
# payload(二进制和配置种子)是私有的,不进仓库,由 device.conf 的 HERALD_PAYLOAD 指向;见 README 的"输入"。
need_input HERALD_PAYLOAD
require_mod required/general/herald-core
for f in bin/keymint bin/inject seed/keybox.xml seed/injector.toml seed/config.toml seed/pif_fingerprint.json seed/vbmeta_state.toml; do
    [[ -f $HERALD_PAYLOAD/$f ]] || die "herald payload 缺 $f($HERALD_PAYLOAD)"
done
OE=u:object_r:herald_exec:s0

# 1. payload:引擎二进制 + 配置种子,放 /system/etc/herald_payload(bin/ 目录和 resetprop 由 herald-core 装),全目录 herald_exec 标签
put_dir etc/herald_payload/seed 0755 0:0 "$OE"
for f in keymint inject; do
    put "$HERALD_PAYLOAD/bin/$f" "etc/herald_payload/bin/$f" 0755 0:0 "$OE"
done
for f in keybox.xml injector.toml config.toml pif_fingerprint.json vbmeta_state.toml; do
    put "$HERALD_PAYLOAD/seed/$f" "etc/herald_payload/seed/$f" 0644 0:0 "$OE"
done

# 2. 接入 herald-core:broker 插件(起守护 + 命令)和 heraldctl 插件。00- 前缀让它先于 app-spoof.sh 等依赖它变量的插件加载
put "$MOD/files/00-attestation.sh"      etc/herald_payload/plugins/00-attestation.sh 0644 0:0 "$OE"
put "$MOD/files/heraldctl-attestation.sh"  etc/heraldctl.d/00-attestation.sh            0644 0:0 u:object_r:system_file:s0

# 3. SELinux:keystore 域放行读 payload / 被回调 / 执行映射注入体,以及 keystore 数据目录下的运行目录
cil_append "attestation-fix: keystore 侧" "$MOD/sepolicy_attestation.cil"

# 4. 默认身份(原 spoof/default-profile,已并入)
# keymint 的默认 profile 改成本机真实身份(原厂固件的指纹、版本、补丁),不再是烤进镜像的 Pixel 7。
# 挂在 herald-core 上(它负责把种子装进 /system/etc/herald_payload/seed/),本模块只替换其中的 pif_fingerprint.json。
need_input STOCK_SYSTEM_IMG
need_input STOCK_VENDOR_IMG
: "${ID_BRAND:?}" "${ID_DEVICE:?}" "${ID_MANUFACTURER:?}" "${ID_MODEL:?}" "${ID_NAME:?}"
m=$WORK/stock; mkdir -p "$m"
sudo mount -o loop,ro "$STOCK_SYSTEM_IMG" "$m"; sudo cat "$m/system/build.prop" > "$WORK/stock_system.prop"; sudo umount "$m"
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m";  sudo cat "$m/build.prop" > "$WORK/stock_vendor.prop"; sudo umount "$m"
python3 -I "$MOD/make_profile.py" "$WORK/stock_system.prop" "$WORK/stock_vendor.prop" \
    --brand "$ID_BRAND" --device "$ID_DEVICE" --manufacturer "$ID_MANUFACTURER" --model "$ID_MODEL" --product "$ID_NAME" \
    > "$WORK/pif_fingerprint.json"
log "默认 profile: $(cat "$WORK/pif_fingerprint.json")"
replace "$WORK/pif_fingerprint.json" etc/herald_payload/seed/pif_fingerprint.json

log "完成(payload $(sha256sum "$HERALD_PAYLOAD/bin/keymint" | cut -c1-12)…)"

# 5. "机型伪装与密钥认证"App(设置 → 关于平板电脑 → 型号下面;没有桌面图标)+ herald-apps 白名单。
#   App 经 herald-apps 通道跑上面这些命令(spoof_on / keybox / rkp);没打 herald-apps 的底包线不装。源码在 app/。
if mod_ran required/general/herald-apps; then
    put_dir system_ext/app/TB321FU-Attest 0755 0:0 u:object_r:system_file:s0
    put "$MOD/files/TB321FU-Attest.apk" system_ext/app/TB321FU-Attest/TB321FU-Attest.apk 0644 0:0 u:object_r:system_file:s0
    put "$MOD/files/com.lenovo.tb321fu.attest.allow" etc/herald_payload/apps/com.lenovo.tb321fu.attest.allow 0644 0:0 u:object_r:herald_exec:s0
else
    log "(没打 required/general/herald-apps,不装机型伪装与密钥认证 App)"
fi
