# 开 32 位 zygote + 声明 32 位 ABI,让 PackageManager 放行 armeabi-v7a 的 APK、system_server 去连 32 位 zygote。
# 做法照小米 14 Ultra(同 SM8650,官方集成 Tango;见 patches/required/general/tango/README.md"参照小米"一节):
#   - 不改 ro.zygote(保持 vendor 的 zygote64),自带一个 zygote_secondary 服务(files/tango-zygote32.rc),由开机保险放行才启动;
#   - ABI 列表显式写进 system build.prop;
#   - ro.dalvik.vm.enable_uffd_gc=false:Tango 不支持 userfaultfd,32 位 ART 只能走 CC GC,而 odrefresh 默认按 CMC 编 32 位启动镜像,
#     两边对不上(V79 真机:read barrier state mismatch),32 位进程就没有启动镜像可用。小米 product/build.prop 也是这么设的。
need_input STOCK_VENDOR_IMG
need_tool python3
need_file bin/app_process32
# bin/boringssl_self_test64:A15 的 system 有、A17(DP11)已把 boringssl 自检独立二进制移除。不强制;
# 下面第 5 步按它在不在决定 tango-boringssl32.rc 带不带"系统侧两条兜底 override"(必须接管的 vendor 那条跟 system 无关)。
need_file etc/init/hw/init.zygote64_32.rc     # 只用来核对服务定义没变(我们自带的那份抄自它)

# 1. 声明 32 位 ABI 会让原厂 vendor 里"只在有 32 位 ABI 时才跑"的服务被触发。带 reboot_on_failure/critical 的,
#    起不来就整机重启(V68 卡第一屏)。tango-boringssl32.rc 接管了已知的那个;再有新的就停,别出一个开不了机的镜像。
m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 vendor 镜像 $STOCK_VENDOR_IMG"; }
bad=$(sudo python3 -I "$MOD/check_vendor32.py" "$m" boringssl_self_test32_vendor) || true
v64=0; sudo test -e "$m/bin/boringssl_self_test64" && v64=1
sudo umount "$m"; rmdir "$m"
if [[ -n $bad ]]; then die "原厂 vendor 有声明 32 位 ABI 后会触发、起不来就重启的服务(需要像 tango-boringssl32.rc 那样接管):$(echo "$bad" | tr '\n' ' ')"; fi
if [[ $v64 != 1 ]]; then die "原厂 vendor 没有 bin/boringssl_self_test64,tango-boringssl32.rc 里 vendor 那条要改"; fi

# 2. 服务定义核对:原版 zygote_secondary 的命令行没变(变了说明底包换了,自带的 rc 要跟着对一遍)
need_grep etc/init/hw/init.zygote64_32.rc '^service zygote_secondary /system/bin/app_process32 -Xzygote /system/bin --zygote --socket-name=zygote_secondary --enable-lazy-preload$'

# 3. ABI 列表。显式写出 abilist,init 就不会再从 vendor 的 ro.vendor.product.cpu.abilist32(空)去派生。
#    ★不写 ro.zygote:V77 真机证明 vendor/build.prop 的 ro.zygote=zygote64 会盖掉 system 的;就算写进 product 盖回来,
#      init 也会 import init.zygote64_32.rc + init.boringssl.zygote64_32.rc,多出两个 32 位自检和 onrestart restart zygote。现在都不要。
prop build.prop ro.product.cpu.abilist arm64-v8a,armeabi-v7a,armeabi --add
prop build.prop ro.product.cpu.abilist32 armeabi-v7a,armeabi --add
prop build.prop ro.product.cpu.abilist64 arm64-v8a --add

# 4. ART 统一用 CC GC(32/64 位启动镜像和运行时一致)。底包的 true 写在 product/etc/build.prop(V881 真机:只改 system 的没用,product 后加载盖掉了);
#    两处都写。odrefresh 会在下次开机重编 /data 下的启动镜像(一次,几分钟)。
need_file product/etc/build.prop
prop product/etc/build.prop ro.dalvik.vm.enable_uffd_gc false --add
prop build.prop ro.dalvik.vm.enable_uffd_gc false --add

# 5. vendor 的 32 位 BoringSSL 自检改跑 64 位那份(它只看 abilist32,不看 ro.zygote),原因见 rc 文件头。
#    system 的两个 32 位自检在 ro.zygote=zygote64 下根本不触发,rc 里那两条 override 只是兜底。
#    A15:system 有 boringssl_self_test64 → 原样打完整 rc(含系统侧兜底)。
#    A17:system 已无该二进制,系统侧两条会引用不存在的文件 → 只打必须接管的 vendor 那条(→ /vendor/bin/boringssl_self_test64)。
sys_bssl64=0; sudo test -e "$SYS/bin/boringssl_self_test64" && sys_bssl64=1
if [[ $sys_bssl64 == 1 ]]; then
    put "$MOD/files/tango-boringssl32.rc" etc/init/tango-boringssl32.rc 0644 0:0 u:object_r:system_file:s0
else
    log "system 无 bin/boringssl_self_test64(A17):tango-boringssl32.rc 只保留 vendor 那条"
    _rc=$(mktemp)
    cat > "$_rc" <<'RC'
# A17:system 已移除 boringssl self-test 独立二进制;只保留必须接管的 vendor 32 位自检。
# 联想 vendor 的 boringssl_self_test.rc 在 on early-init 跑 boringssl_self_test32_vendor(/vendor/bin/boringssl_self_test32,
# 带 reboot_on_failure),vendor 只有 64 位 → 不接管就重启。这里先定义同名服务改跑 /vendor/bin/boringssl_self_test64;
# /system/etc/init 先于 /vendor/etc/init 解析,vendor 那份作为重复定义被 init 丢弃,exec_start 跑这一份,不重启。
service boringssl_self_test32_vendor /vendor/bin/boringssl_self_test64
    setenv BORINGSSL_SELF_TEST_CREATE_FLAG true
    stdio_to_kmsg
    user root
RC
    put "$_rc" etc/init/tango-boringssl32.rc 0644 0:0 u:object_r:system_file:s0
    rm -f "$_rc"
fi

# 6. 32 位 zygote 服务(不动原版 init.zygote64_32.rc)
put "$MOD/files/tango-zygote32.rc" etc/init/tango-zygote32.rc 0644 0:0 u:object_r:system_file:s0

# 7. 开机保险(V82 起带崩溃保护):模块没加载、或上次带 32 位开机没撑到稳定,就撤掉 32 位 ABI、不放行 zygote_secondary,按纯 64 位开机;
#    崩溃现场(pstore)、insmod 结果写到 /metadata/tango_log/,并导出到 /data/local/tmp/tango_log(adb pull 直接取)。
#    heraldctl tango status|retry|off|logs。
put_dir etc/tango 0755 0:0 u:object_r:system_file:s0
put "$MOD/files/tango-guard.sh"  etc/tango/tango-guard.sh  0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tango-stable.sh" etc/tango/tango-stable.sh 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tango-export.sh" etc/tango/tango-export.sh 0755 0:0 u:object_r:herald_exec:s0
put "$MOD/files/tango-guard.rc"  etc/init/tango-guard.rc   0644 0:0 u:object_r:system_file:s0
put "$MOD/files/tango-ctl.sh"    etc/herald_payload/plugins/tango.sh 0644 0:0 u:object_r:herald_exec:s0
put "$MOD/files/heraldctl-tango.sh" etc/heraldctl.d/tango.sh            0644 0:0 u:object_r:system_file:s0
