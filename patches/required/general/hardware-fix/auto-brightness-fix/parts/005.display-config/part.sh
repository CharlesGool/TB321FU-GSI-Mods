# brightness/display-config:把原厂 vendor 的面板亮度配置原样放进 /product/etc/displayconfig/,原理见本目录 README.md。
# 可选补丁 hbm-unlimited 在它后面把同名文件换成放宽 HBM 限制的版本。
need_input STOCK_VENDOR_IMG
m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 vendor 镜像 $STOCK_VENDOR_IMG"; }
mapfile -t XMLS < <(sudo find "$m/etc/displayconfig" -maxdepth 1 -name 'display_id_*.xml' 2>/dev/null)
(( ${#XMLS[@]} > 0 )) || { sudo umount "$m"; rmdir "$m"; die "原厂 vendor 里没有 etc/displayconfig/display_id_*.xml"; }
put_dir product/etc/displayconfig 0755 0:0 u:object_r:system_file:s0
for x in "${XMLS[@]}"; do
    n=$(basename "$x")
    sudo cat "$x" | python3 -I "$TOOLKIT/lib/relax_hbm.py" lux > "$WORK/$n" || die "改 $n 失败"
    put "$WORK/$n" "product/etc/displayconfig/$n" 0644 0:0 u:object_r:system_file:s0
done
sudo umount "$m"; rmdir "$m"
