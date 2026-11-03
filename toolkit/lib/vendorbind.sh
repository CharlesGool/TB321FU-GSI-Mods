# 开机 bind 到 /vendor 的构建端函数。模块在 apply.sh 开头 `source "$TOOLKIT/lib/vendorbind.sh"` 使用。
# 运行端(开机时真正 bind 的脚本和 rc)在 toolkit/vendor-bind/,机制和原理看那里的 README。
# 这是基础设施库,不是模块:第一次调用 vendor_bind_add 时自动把脚本和 rc 装进树里(已经装过就跳过),
# 之后每个调用只追加自己的描述符。所以用它的模块之间互不依赖,谁单独启用、怎么组合都行。
#
# 变量(都有默认值,可以在 device.conf / conf.d 里改):
#   VENDOR_BIND_DEFAULT_LABEL   补丁文件的默认 SELinux 标签,默认 u:object_r:vendor_file:s0
#
# 变量还有:
#   VENDOR_BIND_EXEC_LABEL      开机脚本的标签,默认 u:object_r:update_engine_exec:s0
# 需要 device.conf 里的 DEVICE(脚本里的设备守护用)。
# 依赖 common.sh 里的 put、put_dir、die、log。

# vendor_stock_get <vendor 里的相对路径> <输出文件>
#   从原厂 vendor 镜像($STOCK_VENDOR_IMG)里把一个文件现取出来。文件不在就 die(换了固件时会走到这)。
vendor_stock_get() {
    local rel=$1 out=$2 m
    [[ -n ${STOCK_VENDOR_IMG:-} && -e $STOCK_VENDOR_IMG ]] || die "缺输入 STOCK_VENDOR_IMG(在 device.conf 里设置):${STOCK_VENDOR_IMG:-未设置}"
    m=$(mktemp -d -p "$WORK")
    sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 vendor 镜像 $STOCK_VENDOR_IMG"; }
    if ! sudo test -f "$m/$rel"; then
        sudo umount "$m"; rmdir "$m"; die "原厂 vendor 里没有 $rel,换固件后这个文件可能改了位置"
    fi
    sudo cat "$m/$rel" > "$out"
    sudo umount "$m"; rmdir "$m"
    log "取自原厂 vendor: $rel ($(sha256sum "$out" | cut -c1-12)…)"
}

# _vendor_bind_install    (内部)把开机脚本和 rc 装进树里,幂等。
#   树里已经有一模一样的 → 跳过;有但内容不同 → die(不覆盖别人的文件)。
_vendor_bind_install() {
    local src=$TOOLKIT/vendor-bind tmp
    [[ -f $src/vendor-bind.sh.in && -f $src/vendor-bind.rc ]] || die "缺 $src 下的 vendor-bind.sh.in / vendor-bind.rc"
    [[ -n ${DEVICE:-} ]] || die "device.conf 里没有 DEVICE(开机脚本用 ro.product.vendor.device 做设备守护)"
    tmp=$(mktemp -p "$WORK")
    sed "s/@DEVICE@/$DEVICE/" "$src/vendor-bind.sh.in" > "$tmp"
    grep -q @ "$tmp" && die "vendor-bind.sh 模板没填完"
    if sudo test -e "$SYS/bin/vendor-bind.sh"; then
        sudo cmp -s "$SYS/bin/vendor-bind.sh" "$tmp" && sudo cmp -s "$SYS/etc/init/vendor-bind.rc" "$src/vendor-bind.rc" \
            || die "system/bin/vendor-bind.sh 已存在但和 toolkit/vendor-bind/ 生成的不一样,不覆盖"
        rm -f "$tmp"
    else
        sudo test ! -e "$SYS/etc/init/vendor-bind.rc" || die "system/etc/init/vendor-bind.rc 已存在但没有 vendor-bind.sh,底包状态不对"
        # 标签用 update_engine_exec:init 的 `exec` 要求可执行文件有到别的域的 domain transition,
        # system_file 没有;plat 策略里有 (typetransition init update_engine_exec process update_engine)。V1 起沿用。
        put "$tmp" bin/vendor-bind.sh 0755 0:2000 "${VENDOR_BIND_EXEC_LABEL:-u:object_r:update_engine_exec:s0}"
        put "$src/vendor-bind.rc" etc/init/vendor-bind.rc 0644 0:0 u:object_r:system_file:s0
        rm -f "$tmp"
    fi
    sudo test -d "$SYS/etc/vendor-bind" || put_dir etc/vendor-bind 0755 0:0 u:object_r:system_file:s0
    # Enforcing 下 update_engine 域默认没有 mounton / 读 vendor_file 的权限,不放行的话一个 bind 都做不成(见 vendor-bind.cil)
    cil_append "vendor-bind/sepolicy: update_engine 域 bind /vendor 文件" "$src/vendor-bind.cil"
}

# vendor_bind_add <目标 vendor 路径> <补丁文件> <原文件 sha256> <名字> [补丁文件的 SELinux 标签]
#   登记一个"开机把补丁文件 bind 到 vendor 里这个文件上"的修复。做两件事:
#     1. 补丁文件放进 system/etc/vendor-bind/<名字>.file
#     2. 写描述符 system/etc/vendor-bind/<名字>.bind(target / patch / sha256 三行)
#   开机时 /system/bin/vendor-bind.sh 逐个处理描述符:vendor 里目标文件的 sha256 == 这里给的值才 bind。
#   所以 <原文件 sha256> 必须是"打补丁时用的那个原文件"的 sha256(不是补丁版的!),调用方用 sha256sum 现算,
#   不要写死 —— V66 核对的是旧固件的值,在 A15 设备上永远对不上。
#   补丁文件的标签要和被盖住的 vendor 文件一致(bind 后进程看到的是补丁文件自己的标签):
#   .so 用 u:object_r:vendor_file:s0(默认),音频策略 xml 用 u:object_r:vendor_configs_file:s0。
vendor_bind_add() {
    local target=$1 file=$2 sha=$3 name=$4
    local ctx=${5:-${VENDOR_BIND_DEFAULT_LABEL:-u:object_r:vendor_file:s0}}
    local d=etc/vendor-bind desc
    _vendor_bind_install
    [[ $target == /vendor/* ]]           || die "vendor_bind_add: 目标必须是 /vendor/ 下的绝对路径: $target"
    [[ -f $file ]]                       || die "vendor_bind_add: 补丁文件不存在: $file"
    [[ $sha =~ ^[0-9a-f]{64}$ ]]         || die "vendor_bind_add: sha256 不是 64 位小写十六进制: $sha"
    [[ $name =~ ^[A-Za-z0-9._-]+$ ]]     || die "vendor_bind_add: 名字只能用字母数字 . _ -: $name"
    sudo test ! -e "$SYS/$d/$name.bind"  || die "vendor_bind_add: 名字 $name 已经被别的模块用了"
    if sudo bash -c 'grep -lsx -- "$1" "$2"/*.bind' _ "target=$target" "$SYS/$d" | grep -q .; then
        die "vendor_bind_add: $target 已经有别的描述符了,同一个文件不能被两个补丁盖"
    fi
    put "$file" "$d/$name.file" 0644 0:0 "$ctx"
    desc=$(mktemp -p "$WORK")
    printf 'target=%s\npatch=/system/%s/%s.file\nsha256=%s\n' "$target" "$d" "$name" "$sha" > "$desc"
    put "$desc" "$d/$name.bind" 0644 0:0 u:object_r:system_file:s0
    rm -f "$desc"
    log "vendor-bind: $target <- $name(原文件 sha256 ${sha:0:12}…)"
}
