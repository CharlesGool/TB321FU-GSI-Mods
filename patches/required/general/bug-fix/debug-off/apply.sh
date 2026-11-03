# 关调试:去掉 Mystic 的调试段,ro.secure=1 / ro.adb.secure=1 / ro.debuggable=0,build.prop 权限 0644。
need_file build.prop
need_file system_ext/etc/build.prop

# 1. 删 '# Force ADB' / '# Logcat' 段(Mystic 特有,别的底包没有就跳过)
edit build.prop python3 -I "$MOD/debug_blocks.py"

# 2. 安全属性。key 不存在就追加(这几个值写上总是安全的)
prop build.prop ro.secure 1 --add
prop build.prop ro.adb.secure 1 --add
prop build.prop ro.debuggable 0 --add
prop system_ext/etc/build.prop ro.adb.secure 1 --add

# 3. Mystic 底包的 system/build.prop 是 0600,原厂和 AOSP 都是 0644
#    (App 能直接读这个文件,0600 本身就是异常特征)。edit 会保留权限,所以放在最后改。
sudo chmod 0644 "$SYS/build.prop"

# 4. 核对
sudo grep -qE '^ro\.(debuggable=1|adb\.secure=0|secure=0)' "$SYS/build.prop" && die "调试属性还在"
sudo grep -qxF '# Force ADB' "$SYS/build.prop" && die "Force ADB 段还在"
log "完成"
