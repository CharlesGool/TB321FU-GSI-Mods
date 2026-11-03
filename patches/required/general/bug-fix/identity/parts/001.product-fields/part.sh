# 机型字段:三份 build.prop 里的 ro.product.* 改成 TB321FU(Lenovo),system 里的 flavor/product/description 同步。
need_file build.prop
need_file product/etc/build.prop
need_file system_ext/etc/build.prop
: "${ID_BRAND:?}" "${ID_DEVICE:?}" "${ID_MANUFACTURER:?}" "${ID_MODEL:?}" "${ID_NAME:?}"
export ID_BRAND ID_DEVICE ID_MANUFACTURER ID_MODEL ID_NAME GSI_CODENAME

edit build.prop                 python3 -I "$MOD/product_fields.py" system
edit product/etc/build.prop     python3 -I "$MOD/product_fields.py" product
edit system_ext/etc/build.prop  python3 -I "$MOD/product_fields.py" system_ext

# 核对
sudo grep -q "^ro.product.system.model=$ID_MODEL\$" "$SYS/build.prop" || die "system 的 model 没改成功"
log "完成: $ID_BRAND / $ID_DEVICE / $ID_MODEL"
