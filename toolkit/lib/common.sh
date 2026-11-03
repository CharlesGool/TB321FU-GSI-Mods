# 补丁 apply.sh / part.sh 用的公共函数。由 toolkit/build.sh(runmods.sh)在调用每个补丁前 source。
#
# 可用的环境变量(toolkit/build.sh 提供):
#   TREE      工作树根(等于 GSI 镜像的根,里面有 system/)
#   SYS       $TREE/system
#   MOD       当前模块目录(只读,源码和文件都在这)
#   MOD_NAME  当前模块名
#   WORK      当前模块的临时目录(每次构建清空)
#   TOOLKIT   toolkit/ 目录
#   以及 device.conf 里定义的所有变量(VERSION、STOCK_*、PRIVATE 等)
#
# 约定:
#   - 改树里的文件一律用这里的函数。直接 `sudo sed -i` 会换 inode,丢 SELinux 标签、权限变 0600(V60/V64 踩过)。
#   - 模块对底包有前提(某文件、某个方法、某个 key)时,先用 need_* 检查,不满足就 die。
#     换底包后宁可构建失败,也不要出一个"看起来成功、实际少了改动"的镜像。

set -euo pipefail

die()  { echo "  [$MOD_NAME] 错误: $*" >&2; exit 1; }
log()  { echo "  [$MOD_NAME] $*"; }
warn() { echo "  [$MOD_NAME] 警告: $*" >&2; }

# ---- 前提检查 ----
need_file()   { sudo test -e "$SYS/$1" || die "底包里没有 system/$1,这个模块不适用于当前底包"; }
need_grep()   { sudo grep -q -- "$2" "$SYS/$1" || die "system/$1 里找不到 '$2',底包和模块预期的不一样"; }
need_input()  { [[ -n ${!1:-} && -e ${!1} ]] || die "缺输入 $1(在 device.conf 里设置):${!1:-未设置}"; }
need_tool()   { command -v "$1" >/dev/null || die "缺工具 $1"; }

# ---- 标签 ----
# SELinux 标签按 Android 的习惯带结尾 \0 写入。
label() {  # label <树内绝对路径> <context>
    sudo python3 -I -c 'import os,sys; os.setxattr(sys.argv[1], "security.selinux", sys.argv[2].encode() + b"\0", follow_symlinks=False)' "$1" "$2"
}
get_label() { sudo python3 -I -c 'import os,sys; print(os.getxattr(sys.argv[1], "security.selinux", follow_symlinks=False).rstrip(b"\0").decode())' "$1"; }

# ---- 放文件 ----
# put_dir <system 下的相对路径> <mode> <uid:gid> <context>
#   建目录(已存在就只改属性)。新目录必须显式定标签,不然是 unlabeled(V29 HeraldControl 目录踩过)。
put_dir() {
    local d="$SYS/$1"
    sudo mkdir -p "$d"
    sudo chmod "$2" "$d"; sudo chown "$3" "$d"; label "$d" "$4"
    log "+ system/$1/ ($2 $3 $4)"
}

# put <源文件> <system 下的相对路径> <mode> <uid:gid> <context>
#   父目录必须已经存在(用 put_dir 建),避免 install -D 偷偷建出没标签的目录。
put() {
    local dst="$SYS/$2"
    [[ -f $1 ]] || die "源文件不存在: $1"
    sudo test -d "$(dirname "$dst")" || die "目标目录不存在: system/$(dirname "$2")(先 put_dir)"
    sudo install -m "$3" -o "${4%:*}" -g "${4#*:}" "$1" "$dst"
    label "$dst" "$5"
    log "+ system/$2 ($3 $4 $5)"
}

# replace <源文件> <system 下的相对路径>
#   替换已有文件的内容,保留原来的属主、权限和标签。
replace() {
    local dst="$SYS/$2"
    sudo test -f "$dst" || die "要替换的文件不存在: system/$2"
    [[ -f $1 ]] || die "源文件不存在: $1"
    sudo cp --no-preserve=all "$1" "$dst.herald-new"
    sudo chown --reference="$dst" "$dst.herald-new"; sudo chmod --reference="$dst" "$dst.herald-new"
    label "$dst.herald-new" "$(get_label "$dst")"
    sudo mv -f "$dst.herald-new" "$dst"
    log "~ system/$2"
}

# remove <system 下的相对路径>...   不存在的跳过(返回删除个数到 REMOVED)
remove() {
    REMOVED=0
    local p
    for p in "$@"; do
        if sudo test -e "$SYS/$p" || sudo test -L "$SYS/$p"; then
            sudo rm -rf "$SYS/$p"; log "- system/$p"; REMOVED=$((REMOVED + 1))
        fi
    done
}

# ---- 编辑文本文件 ----
# edit <system 下的相对路径> <命令...>
#   把文件拷到临时位置,执行 `命令... <临时文件>` 就地改,再用 replace 写回(保留属主/权限/标签)。
#   例: edit build.prop python3 -I "$MOD/props.py"
edit() {
    local rel=$1; shift
    local tmp; tmp=$(mktemp -p "$WORK")
    sudo cat "$SYS/$rel" > "$tmp"
    "$@" "$tmp"
    replace "$tmp" "$rel" >/dev/null
    rm -f "$tmp"
    log "~ system/$rel"
}

# append <system 下的相对路径> < 内容     追加内容(保留属主/权限/标签)
append() {
    local rel=$1 tmp; tmp=$(mktemp -p "$WORK")
    sudo cat "$SYS/$rel" > "$tmp"; cat >> "$tmp"
    replace "$tmp" "$rel" >/dev/null; rm -f "$tmp"
    log "~ system/$rel(追加)"
}

# prop <build.prop 相对路径> <key> <value> [--add]
#   把所有 key=... 改成 key=value。key 不存在时:给了 --add 就追加到末尾,否则报错。
prop() {
    local rel=$1 key=$2 val=$3 mode=${4:-}
    edit "$rel" python3 -I "$TOOLKIT/lib/propedit.py" set "$key" "$val" $mode >/dev/null
}

# ---- SELinux 策略 ----
# 追加 CIL 到 plat_sepolicy.cil。toolkit/build.sh 收尾时会把 plat_sepolicy_and_mapping.sha256 清零,
# 让 init 开机时重编策略(哈希对不上就重编)。
cil_append() {  # cil_append <标记名> <cil 文件>
    local CIL=etc/selinux/plat_sepolicy.cil
    if sudo grep -qF "; ==== $1 ====" "$SYS/$CIL"; then log "(plat_sepolicy.cil 已含 $1)"; return; fi
    { echo ""; echo "; ==== $1 ===="; cat "$2"; } | append "$CIL" >/dev/null
    touch "$BUILD_STATE/sepolicy_dirty"
    log "+ plat_sepolicy.cil: $1"
}

fc_append() {  # fc_append <标记注释> < file_contexts 行
    local FC=etc/selinux/plat_file_contexts
    if sudo grep -qF "# $1" "$SYS/$FC"; then log "(plat_file_contexts 已含 $1)"; cat >/dev/null; return; fi
    { echo ""; echo "# $1"; cat; } | append "$FC" >/dev/null
    log "+ plat_file_contexts: $1"
}

# ---- 模块依赖 ----
# require_mod <补丁名>   要求这个补丁已经在本次构建里先跑成功了(MODS 里排在前面)。和 patch.conf 的 REQUIRES 一一对应。
require_mod() {
    [[ -f $BUILD_STATE/ran/${1//\//__} ]] || die "依赖模块 $1,请把它排在本模块前面(MODS 顺序)"
}

# run_parts   合并补丁用:按编号顺序跑 $MOD/parts/NNN.<部分>/part.sh(001.xxx、002.xxx…)。
#   每部分在自己的子 shell 里(变量不串);MOD / WORK 指向这一部分,MOD_NAME=<补丁名>/<部分名>(不带编号)。
#   部分之间的先后就靠编号,不写 require_mod;外部依赖写在补丁的 apply.sh 和 patch.conf 里。
run_parts() {
    local d n=0
    for d in "$MOD"/parts/[0-9][0-9][0-9].*/; do
        [[ -f $d/part.sh ]] || die "部分 $(basename "$d") 没有 part.sh"
        n=$((n + 1))
        ( local_p=$(basename "$d")
          MOD=${d%/} WORK=$WORK/$local_p MOD_NAME=$MOD_NAME/${local_p#*.}
          mkdir -p "$WORK"; log "---- 部分 $local_p"
          source "$MOD/part.sh"; : )
    done
    (( n )) || die "parts/ 下没有 NNN.<部分>/ 文件夹"
}

# mod_ran <补丁名>   这个补丁在本次构建里已经跑过了吗(只返回真假,不报错)。看别的补丁开没开、排没排在前面时用,不要直接查 $BUILD_STATE/ran/。
mod_ran() { [[ -f $BUILD_STATE/ran/${1//\//__} ]]; }

# ---- 贡献:多个模块给同一个产物提改动,由一个 assemble 模块统一处理 ----
# 为什么要有这个:有些产物只能整体重打一次(Wi-Fi APEX 的 payload 要重签、boot 要重签 AVB),
# 但相关的改动又应该各自成一个模块、各自写原理。做法是:贡献者模块只把自己那份"登记"进来,
# 排在最后的 assemble 模块把所有登记的东西一次性应用、打包、签名。
# 登记存在 $BUILD_STATE/contrib/<产物名>/,按登记顺序编号;MODS 里只启用其中几个贡献者,assemble 就只处理这几个。
#
# contrib_add <产物名> <文件> [标记]    登记一个文件(补丁、参数文件…格式由 assemble 模块定);
#                                        标记是校验用的字符串,存成同名 .marker 文件
# contrib_add_text <产物名> <名字> <文本> [标记]   登记一段文本(存成 <名字> 文件)
# contrib_list <产物名>                  按登记顺序列出文件路径(不含 .marker)
# contrib_marker <文件>                  读登记时给的标记(没有就输出空)
# contrib_consume <产物名>               assemble 模块用完后调用;收尾时没被 consume 的产物会让构建失败
contrib_add() {
    local art=$1 f=$2 mark=${3:-} d="$BUILD_STATE/contrib/$1" seq name
    [[ -f $f ]] || die "contrib_add: 文件不存在 $f"
    mkdir -p "$d"
    seq=$(( $(cat "$d/.seq" 2>/dev/null || echo 0) + 1 )); echo "$seq" > "$d/.seq"
    name=$(printf '%03d-%s-%s' "$seq" "${MOD_NAME//\//_}" "$(basename "$f")")
    cp "$f" "$d/$name"
    [[ -n $mark ]] && printf '%s' "$mark" > "$d/$name.marker"
    log "登记到 $art: $name"
}
contrib_add_text() {
    local tmp; tmp=$(mktemp -p "$WORK")
    printf '%s\n' "$3" > "$tmp.$2"; mv "$tmp.$2" "$WORK/$2"; rm -f "$tmp"
    contrib_add "$1" "$WORK/$2" "${4:-}"
}
contrib_list()    { ls "$BUILD_STATE/contrib/$1" 2>/dev/null | grep -v -e '\.marker$' | sed "s|^|$BUILD_STATE/contrib/$1/|"; }
contrib_marker()  { cat "$1.marker" 2>/dev/null || true; }
contrib_consume() { mkdir -p "$BUILD_STATE/contrib/$1"; touch "$BUILD_STATE/contrib/$1/.consumed"; }

# ---- 改动标记:让"善后"类模块知道前面有没有改过某个文件 ----
# 例如 stale-boot-image 只在 framework.jar / services.jar 真的被改过时才去删过期的预编译产物。
# 改了会让别的东西失效的文件(jar、sepolicy…)的模块,改完调用 mark_modified;善后模块用 was_modified 判断。
# mark_modified <system 下的相对路径>     was_modified <路径>(返回 0 = 改过)
mark_modified() { mkdir -p "$BUILD_STATE/modified"; : > "$BUILD_STATE/modified/${1//\//__}"; log "标记已改动: $1"; }
was_modified()  { [[ -f $BUILD_STATE/modified/${1//\//__} ]]; }
