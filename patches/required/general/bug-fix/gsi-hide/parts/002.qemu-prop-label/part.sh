# qemu.sf.lcd_density 的属性标签 qemu_sf_lcd_density_prop 只有模拟器会用。进程 /proc/self/maps 里出现
# /dev/__properties__/u:object_r:qemu_sf_lcd_density_prop:s0 就是虚拟机痕迹。改成 exported_default_prop。
# 只看映射行,不看注释(文件里有一行注释也提到这个类型名,V66 也保留了那条注释)
PC=etc/selinux/plat_property_contexts
if sudo grep -qE '^qemu\.sf\.lcd_density[[:space:]]+u:object_r:qemu_sf_lcd_density_prop' "$SYS/$PC"; then
    edit "$PC" sed -i -E 's|^(qemu\.sf\.lcd_density[[:space:]]+u:object_r:)qemu_sf_lcd_density_prop|\1exported_default_prop|'
    if sudo grep -qE '^qemu\.sf\.lcd_density[[:space:]]+u:object_r:qemu_sf_lcd_density_prop' "$SYS/$PC"; then die "qemu 标签没改掉"; fi
else
    log "(plat_property_contexts 里没有 qemu.sf.lcd_density 的映射行,跳过)"
fi
