#!/system/bin/sh
# Compile the device's current policy + herald_quiet.cil with the same secilc command init uses,
# without loading anything. Run as root (ush), after:
#   adb push herald_quiet.cil test_compile_on_device.sh /data/local/tmp/
#   adb shell 'ush -c "sh /data/local/tmp/test_compile_on_device.sh"'
set -e
cd /data/local/tmp
cat /system/etc/selinux/plat_sepolicy.cil herald_quiet.cil > plat_quiet.cil
VER=$(cat /vendor/etc/selinux/plat_sepolicy_vers.txt)
PV=$(cat /sys/fs/selinux/policyvers)
run() {
  /system/bin/secilc "$1" -m -M true -G -N -c "$PV" \
    /system/etc/selinux/mapping/$VER.cil /system/etc/selinux/mapping/$VER.compat.cil \
    /system_ext/etc/selinux/system_ext_sepolicy.cil /product/etc/selinux/product_sepolicy.cil \
    /vendor/etc/selinux/plat_pub_versioned.cil /vendor/etc/selinux/vendor_sepolicy.cil \
    -o "$2" -f /sys/fs/selinux/null
  echo "$1 -> rc=$? size=$(stat -c %s "$2")"
}
run /system/etc/selinux/plat_sepolicy.cil base.bin
run /data/local/tmp/plat_quiet.cil quiet.bin
rm -f base.bin quiet.bin plat_quiet.cil
