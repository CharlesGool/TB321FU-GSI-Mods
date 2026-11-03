# brightness/hbm-unlimited:手动拉满亮度条就是面板真正的最高亮度(含 HBM),不再要求强光和时间限制。原理见 README.md。
# 做法:从原厂 vendor 取 display_id_*.xml,放宽 <highBrightnessMode> 的限制,放进 /product/etc/displayconfig/
# (DisplayDeviceConfig 先找 product 目录再找 vendor 目录,所以 product 里的这份会盖过 vendor 的)。
need_input STOCK_VENDOR_IMG
need_tool python3
m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 vendor 镜像 $STOCK_VENDOR_IMG"; }
mapfile -t XMLS < <(sudo find "$m/etc/displayconfig" -maxdepth 1 -name 'display_id_*.xml' 2>/dev/null)
(( ${#XMLS[@]} > 0 )) || { sudo umount "$m"; rmdir "$m"; die "原厂 vendor 里没有 etc/displayconfig/display_id_*.xml"; }
put_dir product/etc/displayconfig 0755 0:0 u:object_r:system_file:s0
for x in "${XMLS[@]}"; do
    n=$(basename "$x"); out=$WORK/$n
    sudo cat "$x" | python3 -I "$TOOLKIT/lib/relax_hbm.py" full > "$out" || { sudo umount "$m"; rmdir "$m"; die "改 $n 失败"; }
    put "$out" "product/etc/displayconfig/$n" 0644 0:0 u:object_r:system_file:s0
done
sudo umount "$m"; rmdir "$m"
