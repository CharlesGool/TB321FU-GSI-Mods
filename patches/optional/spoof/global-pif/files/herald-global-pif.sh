#!/system/bin/sh
# V30 全局 PIF 覆写(rootless)。由 init 在 post-fs-data 阶段、u:r:herald 域拉起(见 init.herald.rc)。
# 目的:把当前 PIF profile 的 build 身份属性用 resetprop 全局覆写,赶在 zygote 加载 android.os.Build
#   类、把静态字段从属性读死冻结之前(Build.* 是 class-load 时算一次的 static final,之后 fork 出的
#   所有 app——包括 gms.unstable——都只是继承这份已冻结的值,不会重新读属性)。
# ★只留"必须早"的部分:boot-state(verifiedbootstate/locked 等)是运行时读、非冻结,已挪到
#   herald-start.sh 在 boot_completed 后跑(对照 OMK 原版 service.sh 本来就在那跑,不在 post-fs-data)。
# ★V29b/V30 根因修复(对照 test-results/20261029-v27depif-v29b-diag.md 的因果实验):
#   V29 这里原本逐属性 exec resetprop 近 70 次、串行跑在 post-fs-data —— 这正是 PackageManagerService
#   建 packages.list(uid→包名映射)的同一临界窗口,串行子进程 exec 的 CPU 占用把这个窗口拖慢到让
#   OMK 的包名解析抓到空快照 → keystore 请求 100% packages=[]→RejectedUnknownPackage。
#   修复:① 属性列表收紧到 proven 13 个(= V28 诊断时从验证过的 OMK zygisk PIF .so 自身 strings 里
#   抓出的、它亲自钩的那组 ro.build.*/ro.product.* —— 不是我们猜的,是从能过认证的原配置反推出来的
#   确定有效集,去掉我之前加的 9 份分区指纹冗余 + 25 份分区 product 字段冗余,这些没有证据支撑);
#   ② 这 13 次 resetprop 改成并行 exec(背景 & + wait),而不是串行,把窗口压到约 1 次调用的墙钟时间。
# profile 来源:优先 /data(App 切换/导入后写的),否则回落 /system 烤入的默认种子(首 boot)。
# 默认不伪装:需 $CFG/data/global_pif_enabled 存在(控制 App「应用」/ broker set 会创建它)才真正覆写。
set -u
export LD_LIBRARY_PATH="/apex/com.android.runtime/lib64:/apex/com.android.runtime/lib64/bionic:/system/lib64:/vendor/lib64"

RESETPROP=/system/etc/herald_payload/bin/resetprop
CFG=/data/misc/keystore/herald
ENABLE_FLAG=$CFG/data/global_pif_enabled
DATA_PROFILE=$CFG/data/pif_fingerprint.json
SEED_PROFILE=/system/etc/herald_payload/seed/pif_fingerprint.json
LOGDIR=$CFG/logs
LOG=$LOGDIR/global-pif.log

log() { echo "[global-pif] $*"; /system/bin/log -t herald-global-pif "$*" 2>/dev/null; mkdir -p "$LOGDIR" 2>/dev/null; echo "[$(date 2>/dev/null)] $*" >> "$LOG" 2>/dev/null; }

# spoof/app-spoof(按 App 伪装)的配置文件:每次开机先删,只有"伪装开着 + app 模式"才在下面重新写。
#   framework 里的 PropImitationHooks 在 zygote 里读它,读不到就什么都不做(= global 模式或伪装关着)。
IMIT=/data/system/imitation.conf
APPSPOOF_DIR=/system/etc/herald_payload/app-spoof
rm -f "$IMIT" "$IMIT.tmp"

[ -x "$RESETPROP" ] || { log "resetprop 不可用($RESETPROP),跳过全局 PIF"; exit 0; }
[ -f "$ENABLE_FLAG" ] || { rm -f /data/system/build.prop; log "全局 PIF 默认关闭(无 $ENABLE_FLAG);用控制 App「应用」或 broker set 开启"; exit 0; }

# 选 profile:优先 /data(App 切换/导入后写的),必须"有 fingerprint 且 release 非空";否则回落
# /system 稳定 seed。★2026-10-29 用户明确要求允许 CANARY/beta release(原话:"原来就是那么实现的,
# 说明是可以这么做的"——最初验证过能过认证的那套配置[panther_beta]本来就是 CANARY release,Android
# 历史上长期用非数字 codename,框架本身不拿 RELEASE 当整数跑真实逻辑分支;parseInt 风险只在某些不
# 规范的第三方 app 自己写的代码,不是系统级风险)。不再按"是否纯数字"判定有效性,只要求非空。
valid_profile() {
    # V72:只要求有 fingerprint。brand/device/release/id/incremental 等缺的字段下面从 fingerprint 里推出来
    # (V71 真机:keymint apply 写出的 profile 只有 model/product/fingerprint/security_patch 等 7 个字段,
    #  旧版因为 release 为空整份作废、回落到 /system seed——而 V68 起 seed 是本机真实身份,于是"全局伪装开着却什么都没变")
    _f=$1; [ -f "$_f" ] || return 1
    grep -q '"fingerprint":"[^"]' "$_f" 2>/dev/null || return 1
    return 0
}
PROFILE=""
if valid_profile "$DATA_PROFILE"; then PROFILE=$DATA_PROFILE
elif valid_profile "$SEED_PROFILE"; then PROFILE=$SEED_PROFILE
fi
[ -n "$PROFILE" ] || { log "无有效 PIF profile(release 为空,/system seed 亦无效),跳过"; exit 0; }
log "用 profile=$PROFILE"

# 单行扁平 JSON 字段提取(toybox sed 兼容)。字符串取 "k":"v",数字取 "k":n。
# ★V37 修复 Bug2(2026-10-29 用户实测复现):keymint 的 --webui-apply-pif-fingerprint 写出的
#   profile 会把 fingerprint 里的 "/" 转义成合法但少见的 "\/"(JSON 规范允许但不要求转义 /);
#   之前直接把带 \/ 的原始字符串传给 resetprop,导致真实 ro.build.fingerprint 里混进了字面反斜杠
#   (用户截图:google\/tangorpro_beta\/tangorpro:CANARY\/... )。我们自己写的 seed 没这个转义、
#   没触发过。统一在提取后反转义,不止 fingerprint——以防其它字段也遇到同样来源。
jstr() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" "$PROFILE" | head -1 | sed 's#\\/#/#g'; }
jnum() { sed -n "s/.*\"$1\":\\([0-9][0-9]*\\).*/\\1/p" "$PROFILE" | head -1; }

FP=$(jstr fingerprint)
BRAND=$(jstr brand)
DEVICE=$(jstr device)
MODEL=$(jstr model)
MFR=$(jstr manufacturer)
PRODUCT=$(jstr product)
RELEASE=$(jstr release)
BID=$(jstr id)
INCR=$(jstr incremental)
BTYPE=$(jstr build_type)
TAGS=$(jstr tags)
SPATCH=$(jstr security_patch)
SDK=$(jnum device_initial_sdk_int)

# V72:缺的字段从 fingerprint(brand/product/device:release/id/incremental:type/tags)推。profile 里有的优先。
if [ -n "$FP" ]; then
    _t=$(echo "$FP" | cut -d: -f2-)                      # release/id/incremental:type/tags
    [ -n "$BRAND" ]   || BRAND=$(echo "$FP" | cut -d/ -f1)
    [ -n "$PRODUCT" ] || PRODUCT=$(echo "$FP" | cut -d/ -f2)
    [ -n "$DEVICE" ]  || DEVICE=$(echo "$FP" | cut -d/ -f3 | cut -d: -f1)
    [ -n "$RELEASE" ] || RELEASE=$(echo "$_t" | cut -d/ -f1)
    [ -n "$BID" ]     || BID=$(echo "$_t" | cut -d/ -f2)
    [ -n "$INCR" ]    || INCR=$(echo "$_t" | cut -d/ -f3 | cut -d: -f1)
    [ -n "$BTYPE" ]   || BTYPE=$(echo "$_t" | cut -d: -f2 | cut -d/ -f1)
    [ -n "$TAGS" ]    || TAGS=$(echo "$_t" | cut -d: -f2 | cut -d/ -f2-)
    if [ -z "$MFR" ]; then   # 品牌首字母大写:google -> Google
        MFR="$(echo "$BRAND" | cut -c1 | tr 'a-z' 'A-Z')$(echo "$BRAND" | cut -c2-)"
    fi
    log "字段补全(从 fingerprint 推): brand=$BRAND device=$DEVICE manufacturer=$MFR release=$RELEASE id=$BID incremental=$INCR type=$BTYPE tags=$TAGS"
fi

[ -n "$FP" ] || { log "profile 无 fingerprint,跳过(避免写坏属性)"; exit 0; }
# ★用户明确要求允许 CANARY/beta release(见上面 valid_profile 的说明),这里只守住"非空"这一条
# 真正会写坏属性的底线,不再按数字格式拒绝。
[ -n "$RELEASE" ] || { log "release 为空,拒绝全局应用(避免写坏属性)"; exit 0; }

# ---- 按 App 伪装(spoof/app-spoof 装了,且模式不是 global):不改任何系统属性,只写配置文件给 zygote ----
#   模式文件 $CFG/data/spoof_mode(heraldctl spoofmode app|global 写),没有 = app。名单 = 默认 + 额外。
SPOOF_MODE=$(cat "$CFG/data/spoof_mode" 2>/dev/null)
if [ -f "$APPSPOOF_DIR/targets.default" ] && [ "$SPOOF_MODE" != global ]; then
    {
        _seen=" "   # V89:默认名单和额外名单重复的只写一次(V86 真机 imitation.conf 里 gms.unstable、vending 各两次)
        # V91:injector.toml 的 scoop(走伪装 keymint 的 App)也并进名单:它们拿到的认证证书是 profile 身份和补丁级别,
        #   Build.* 也得是 profile 的,否则证书和 Build 对不上(V88 真机:补丁级别证书 2026-10-05 / Build 2025-05-05)
        { cat "$APPSPOOF_DIR/targets.default" "$CFG/data/app_spoof_targets" 2>/dev/null
          sed -n '/^scoop *= *\[/,/\]/{s/[][",]/ /g;s/^ *scoop *= *//;p}' "$CFG/injector.toml" 2>/dev/null | tr ' ' '\n'
        } | while IFS= read -r _t; do
            case "$_t" in ""|*[!A-Za-z0-9._:]*) continue ;; esac
            case "$_seen" in *" $_t "*) continue ;; esac
            _seen="$_seen$_t "; echo "TARGET=$_t"
        done
        echo "FINGERPRINT=$FP"
        echo "ID=$BID"
        echo "DISPLAY=$BID"
        echo "TAGS=$TAGS"
        echo "TYPE=$BTYPE"
        echo "BRAND=$BRAND"
        echo "DEVICE=$DEVICE"
        echo "MANUFACTURER=$MFR"
        echo "MODEL=$MODEL"
        echo "PRODUCT=$PRODUCT"
        echo "VERSION.RELEASE=$RELEASE"
        echo "VERSION.RELEASE_OR_CODENAME=$RELEASE"
        echo "VERSION.INCREMENTAL=$INCR"
        echo "VERSION.SECURITY_PATCH=$SPATCH"
        [ -n "$SDK" ] && echo "VERSION.DEVICE_INITIAL_SDK_INT=$SDK"
    } > "$IMIT.tmp" 2>/dev/null
    chown 0:0 "$IMIT.tmp" 2>/dev/null; chmod 0600 "$IMIT.tmp" 2>/dev/null
    if grep -q '^TARGET=' "$IMIT.tmp" 2>/dev/null && chcon u:object_r:imitation_conf_file:s0 "$IMIT.tmp" 2>/dev/null; then
        mv -f "$IMIT.tmp" "$IMIT"
        log "按 App 伪装:配置已写 $IMIT(名单 $(grep -c '^TARGET=' "$IMIT") 个),系统属性不改: fp=$FP model=$MODEL patch=$SPATCH"
    else
        rm -f "$IMIT.tmp"
        log "按 App 伪装:配置写不成(名单空或 chcon 失败),这次开机不伪装;系统属性也不改"
    fi
    exit 0
fi
log "全局模式(spoof_mode=${SPOOF_MODE:-未设};app-spoof 模块$([ -f "$APPSPOOF_DIR/targets.default" ] && echo 已装 || echo 没装)):resetprop 改全局属性"

# ---- proven 13 属性(来自能过认证的原配置自带 zygisk PIF .so 亲自钩的那组)+ V37 新增 2 个
#      (release_or_codename/display.id,2026-10-29 用户实测坐实漏了这两个,都是纯字符串、不驱动
#      任何系统代码分支,风险等级和其余 13 个一样;不含 ro.build.version.sdk——那个驱动大量真实
#      兼容性判断代码路径,风险等级不同,留给用户决定是否要冒这个险,暂不自动覆盖),并行 exec + wait ----
rp() { # rp <prop> <value> —— 后台起;-n 直改属性区不触发
  # ★用户实测坐实:值为空就静默跳过,之前连日志都不记——某条字段(常见是 App 表单留空提交的)
  #   被跳过时,其它字段正常改了,拼出"Lenovo Pixel Tablet"这种一半伪装一半真机的怪异组合,
  #   排查起来全靠猜。V41 加上:App 层已挡掉空值提交,这里再补一道日志,万一还是漏了能查。
  if [ -n "$2" ]; then "$RESETPROP" -n "$1" "$2" 2>/dev/null &
  else log "跳过 $1(值为空,未写入——profile 里这个字段留空了)"; fi
}
rp ro.build.fingerprint "$FP"
rp ro.build.id "$BID"
rp ro.build.display.id "$BID"                    # ★Bug1:之前完全没盖,烤着我们自己的版本串,最明显的破绽
rp ro.build.tags "$TAGS"
rp ro.build.type "$BTYPE"
rp ro.build.version.incremental "$INCR"
rp ro.build.version.release "$RELEASE"
rp ro.build.version.release_or_codename "$RELEASE"   # ★Bug1:Settings"关于手机"读的是这个,之前没盖
rp ro.build.version.security_patch "$SPATCH"
rp ro.product.brand "$BRAND"
rp ro.product.device "$DEVICE"
[ -n "$SDK" ] && rp ro.product.first_api_level "$SDK"
rp ro.product.manufacturer "$MFR"
rp ro.product.model "$MODEL"
rp ro.product.name "$PRODUCT"
wait

# ---- V76:磁盘上的 /system/build.prop 跟着伪装(检测工具比的是"运行时属性 vs build.prop 文件",V75 真机 Hunter 报 6 条不一致)----
# 做法:把 /system/build.prop 里这 15 个键的值换成 profile 的,存成 /dev/herald_build.prop,bind 到 /system/build.prop 上。
#   全程 fail-soft:任何一步不对就不盖,保持原状(最坏结果 = 回到 V75)。herald 域 permissive,所以 chcon/mount 不需要另加策略;
#   mount 需要 CAP_SYS_ADMIN(init.herald-globalpif.rc 给了)。逐行 read 不起子进程(mksh 没有内建 printf,用 echo)。
#   只有伪装开着的那次开机才会走到这里(上面没开就 exit 了),所以关伪装重启后 /system/build.prop 自然是原文件。
# ★V77(V76 真机:另一款检测软件报 SYSTEM_PARTITION_WRITABLE 和 ACTIVE_STACKED_FS_OVER_SYSTEM fs=tmpfs):
#   替换文件从 tmpfs 的 /dev 挪到 /data/system/build.prop(真实文件系统;挂载表 root 列显示 /system/build.prop,不带 herald 字样),
#   bind 之后再 remount,bind,ro,挂载选项变成 ro。
BP_SRC=/system/build.prop
BP_OUT=/data/system/build.prop
sync_buildprop() {
    [ -f "$BP_SRC" ] || { log "build.prop 同步: $BP_SRC 不存在,跳过"; return; }
    grep -q " $BP_SRC " /proc/self/mountinfo 2>/dev/null && { log "build.prop 同步: $BP_SRC 已被盖过,跳过"; return; }
    # echo 在不同 sh 里对反斜杠的处理不一样,文件里有反斜杠就不碰(原版 build.prop 没有)
    grep -qF '\' "$BP_SRC" 2>/dev/null && { log "build.prop 同步: 原文件含反斜杠,不盖"; return; }
    [ -d "${BP_OUT%/*}" ] || { log "build.prop 同步: ${BP_OUT%/*} 不存在,跳过"; return; }
    rm -f "$BP_OUT.tmp"
    : > "$BP_OUT.tmp" || return
    _n=0
    while IFS= read -r _l || [ -n "$_l" ]; do
        _n=$((_n + 1))
        case "$_l" in
            ro.build.fingerprint=*)                 [ -n "$FP" ]      && _l="ro.build.fingerprint=$FP" ;;
            ro.build.id=*)                          [ -n "$BID" ]     && _l="ro.build.id=$BID" ;;
            ro.build.display.id=*)                  [ -n "$BID" ]     && _l="ro.build.display.id=$BID" ;;
            ro.build.tags=*)                        [ -n "$TAGS" ]    && _l="ro.build.tags=$TAGS" ;;
            ro.build.type=*)                        [ -n "$BTYPE" ]   && _l="ro.build.type=$BTYPE" ;;
            ro.build.version.incremental=*)         [ -n "$INCR" ]    && _l="ro.build.version.incremental=$INCR" ;;
            ro.build.version.release=*)             [ -n "$RELEASE" ] && _l="ro.build.version.release=$RELEASE" ;;
            ro.build.version.release_or_codename=*) [ -n "$RELEASE" ] && _l="ro.build.version.release_or_codename=$RELEASE" ;;
            ro.build.version.security_patch=*)      [ -n "$SPATCH" ]  && _l="ro.build.version.security_patch=$SPATCH" ;;
            ro.product.brand=*)                     [ -n "$BRAND" ]   && _l="ro.product.brand=$BRAND" ;;
            ro.product.device=*)                    [ -n "$DEVICE" ]  && _l="ro.product.device=$DEVICE" ;;
            ro.product.first_api_level=*)           [ -n "$SDK" ]     && _l="ro.product.first_api_level=$SDK" ;;
            ro.product.manufacturer=*)              [ -n "$MFR" ]     && _l="ro.product.manufacturer=$MFR" ;;
            ro.product.model=*)                     [ -n "$MODEL" ]   && _l="ro.product.model=$MODEL" ;;
            ro.product.name=*)                      [ -n "$PRODUCT" ] && _l="ro.product.name=$PRODUCT" ;;
        esac
        echo "$_l"
    done < "$BP_SRC" > "$BP_OUT.tmp"
    # 核对:行数一样、指纹行是新值,不然不盖
    _m=$(grep -c '' "$BP_OUT.tmp" 2>/dev/null)
    if [ "$_m" != "$_n" ]; then log "build.prop 同步: 行数对不上($_n -> $_m),不盖"; rm -f "$BP_OUT.tmp"; return; fi
    if grep -q '^ro.build.fingerprint=' "$BP_OUT.tmp" && ! grep -qxF "ro.build.fingerprint=$FP" "$BP_OUT.tmp"; then
        log "build.prop 同步: 指纹行没换成新值,不盖"; rm -f "$BP_OUT.tmp"; return
    fi
    chmod 0644 "$BP_OUT.tmp"; chown 0:0 "$BP_OUT.tmp" 2>/dev/null
    chcon u:object_r:system_file:s0 "$BP_OUT.tmp" 2>/dev/null || { log "build.prop 同步: chcon 失败,不盖"; rm -f "$BP_OUT.tmp"; return; }
    mv -f "$BP_OUT.tmp" "$BP_OUT"
    if ! /system/bin/mount -o bind "$BP_OUT" "$BP_SRC" 2>/dev/null; then log "build.prop 同步: mount -o bind 失败,保持原文件"; return; fi
    # V80 真机:`mount -o remount,bind,ro` 后挂载表这一行仍是 rw。换几种写法逐个试,每次读 mountinfo 核对第 6 列(本挂载的选项)
    _ro=""
    for _how in "remount,bind,ro|1" "bind,remount,ro|1" "remount,ro,bind|2" "ro,remount,bind|2"; do
        _o=${_how%|*}
        if [ "${_how#*|}" = 1 ]; then /system/bin/mount -o "$_o" "$BP_SRC" >> "$LOG" 2>&1
        else /system/bin/mount -o "$_o" "$BP_OUT" "$BP_SRC" >> "$LOG" 2>&1; fi
        _opt=$(grep " $BP_SRC " /proc/self/mountinfo 2>/dev/null | tail -1 | cut -d' ' -f6)
        case "$_opt" in ro|ro,*) _ro=$_o; break ;; esac
    done
    if [ -n "$_ro" ]; then log "build.prop 同步: 已盖到 $BP_SRC($_n 行,只读,用 -o $_ro)"
    else log "build.prop 同步: 已盖到 $BP_SRC($_n 行),但只读重挂载几种写法都没成功,挂载选项仍是 ${_opt:-?}"; fi
}
# ★V97 恢复挂载(V96 去掉挂载后用户实测"更糟糕",退回 V77–V95 的做法):源文件在 /data/system(真实文件系统,
#   不是 tmpfs),bind 后重挂成 ro。已知代价:挂载表里多一行 /system/build.prop,检测软件可能抓到。
sync_buildprop

# ★V37 曾用"重启 zygote"修 Bug3(2026-10-29 用户用 Hunter App 实测抓到:native getprop 显示已伪装的
#   security_patch,但 Java 层 Build.VERSION.SECURITY_PATCH 还是真实值——android.os.Build 的静态字段
#   是 zygote 加载 Build 类那一刻从属性读死冻结的,上面这些 resetprop 和 zygote 自己的启动是一场竞速)。
# ★V46 改成根治而不是补救:init.herald.rc 把 `start herald_globalpif`(异步,init 发完命令立刻往下走,
#   不等脚本跑完)改成了 `exec_start herald_globalpif`(同步阻塞,init 必须等这个脚本完全退出才会继续
#   处理后面的 trigger)。查过 hw/init.rc:late-init 里 trigger post-fs-data 之后隔了几个 trigger
#   才到 trigger zygote-start,但原来用 start 不卡这几步,属性还没写完 zygote 就可能先启动了,这才是
#   Bug3 的真正成因(不是"写得不够快",是"init 压根没等")。换成 exec_start 后属性写入和 zygote 启动
#   不再是竞速,是硬顺序:wait(上面)已经保证本脚本退出前全部属性落地,脚本一退出 init 才会继续走到
#   zygote-start,zygote 物理上不可能在属性写完前起来,不再需要任何形式的重启。
# 副作用也一并解决:V37 的 zygote 重启会让 /sys/fs/selinux/status 的 sequence 计数跳动但没有配套的
# policyload(没有真的重载 sepolicy),被 Duck Detector/春秋 当成 KernelSU 热改 sepolicy 的特征抓到
# ("app_zygote seqno split" / "status.sequence/policyload" 两边查的是同一个 selinuxfs 节点)。改成
# exec_start 后开机全程不会再有任何形式的 zygote 重启,这个误报的根也一起拔掉了。
log "全局 PIF(15 属性,并行,exec_start 硬顺序保证先于 zygote)应用完成: fp=$FP model=$MODEL release=$RELEASE patch=$SPATCH sdk=$SDK"
