#!/usr/bin/env bash
# 交互式从头出 9008 刷机包:一步一步问(原厂 9008 包和 GSI 在哪、工作目录、版本、相机、Google 精简、可选功能、调试),
# 确认后自动:解压原厂 9008 → 切出 vendor 等分区 → 构建 → 出完整的 9008 刷机包(原厂包整套换上新 system,可直接刷;增量补丁另外做)。
# 用法: ./make-9008.sh [device.conf]        默认 devices/tb321fu-a15/device.conf
# 选择存成 <工作目录>/out/wizard-profile.txt(副本 out/wizard-last-profile.txt),同一份以后可以 make 9008 PROFILE=… 重跑。
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd); TOOLKIT=$REPO/toolkit
CONF=$(realpath "${1:-$REPO/devices/tb321fu-a15/device.conf}"); DEVICE_DIR=$(dirname "$CONF")
[[ -t 0 ]] || { echo "要在终端里跑(要回答问题)。不想问就用 make 9008,见 Makefile 开头" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"; source "$TOOLKIT/lib/select.sh"
OLD_DIR=${TB321FU_DATA:-$(cd "$REPO/../tb321fu_pixelos_15_tangorpro_ap3a.241005.015" && pwd)}
title() { ( TITLE=; source "$REPO/patches/$1/patch.conf"; echo "$TITLE" ); }
desc()  { ( DESC=;  source "$REPO/patches/$1/patch.conf"; echo "$DESC" ); }
risks() { ( RISKS=; source "$REPO/patches/$1/patch.conf"; echo "$RISKS" ); }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ask <提示> <默认 y|n> → 0 表示 yes
ask() {
    local a d=$2 hint; [[ $d == y ]] && hint='Y/n' || hint='y/N'
    while :; do
        read -r -p "$1 [$hint] " a; a=${a:-$d}
        case ${a,,} in y|yes|是) return 0 ;; n|no|否) return 1 ;; esac
        echo "  请回答 y 或 n"
    done
}
# choose <提示> <默认> <合法值…> → CHOICE
choose() {
    local p=$1 d=$2 a; shift 2
    while :; do
        read -r -p "$p [默认 $d] " a; a=${a:-$d}
        for v in "$@"; do [[ $a == "$v" ]] && { CHOICE=$a; return; }; done
        echo "  请输入 $* 之一"
    done
}
# ask_path <提示> <默认> <检查函数> → PATH_ANS(展开 ~,检查通过才返回)
ask_path() {
    local p=$1 d=$2 chk=$3 a
    while :; do
        read -r -e -p "$p${d:+ [默认 $d]} " a; a=${a:-$d}; a=${a/#\~/$HOME}
        [[ -n $a ]] || { echo "  必填"; continue; }
        if "$chk" "$a"; then PATH_ANS=$(realpath "$a"); return; fi
    done
}

echo "=================== 出 9008 刷机包($(basename "$DEVICE_DIR"))==================="
echo "会一步一步问你,最后确认后才开始动手。必选补丁(修复、精简、核心)一定会打,只问你能选的。"

# ---------- 0 环境 ----------
say "0. 检查环境"
miss=()
for c in sudo java python3 7z xdelta3 mkfs.erofs apktool aapt2 zipalign apksigner openssl unzip; do command -v "$c" >/dev/null || miss+=("$c"); done
(( ${#miss[@]} == 0 )) || { echo "缺工具: ${miss[*]}(装好再跑)" >&2; exit 1; }
echo "  工具齐全。构建要用 sudo(保留属主和 SELinux 标签),先验证一下:"
sudo -n true 2>/dev/null || sudo -v || { echo "sudo 不通过" >&2; exit 1; }

# ---------- 1 输入 ----------
say "1. 输入文件在哪"
chk_stock() {
    if [[ -f $1 && $1 == *.7z ]]; then return 0; fi
    if [[ -d $1/image && -e $1/image/contents.xml ]] || [[ -d $1 && -e $1/contents.xml ]]; then return 0; fi
    echo "  要么是原厂 9008 的 .7z,要么是解出来的目录(里面有 image/ 或 contents.xml)"; return 1
}
chk_gsi() {
    if [[ -f $1 && ( $1 == *.zip || $1 == *.img ) ]]; then return 0; fi
    echo "  要是 GSI 的 .zip(里面有 out/…/*.img)或解出来的 .img"; return 1
}
def_stock=$(ls "$OLD_DIR"/inputs/stock-9008/*.7z 2>/dev/null | head -1 || true)
echo "  原厂 9008 包(TB321FU_ZUI_17.0.12_OPEN_9008FACTORY_CRACKED.7z,或已经解出来的目录)"
ask_path "   路径?" "$def_stock" chk_stock; STOCK_SRC=$PATH_ANS
def_gsi=${BASE_GSI:-}; [[ -f $def_gsi ]] || def_gsi=$(ls "$OLD_DIR"/inputs/base/*.zip 2>/dev/null | head -1 || true)
echo "  GSI 底包(Mystic GSI,Pixel Tablet tangorpro A15 AP3A.241005.015;zip 或解出来的 img)"
ask_path "   路径?" "$def_gsi" chk_gsi; GSI_SRC=$PATH_ANS
echo "  工作目录:解压、构建中间产物和输出都放这里。必须是本机磁盘(NAS 不支持保留属主/标签),要约 40GB 空闲。"
chk_work() {
    local fs; mkdir -p "$1" 2>/dev/null || { echo "  建不了 $1"; return 1; }
    fs=$(stat -f -c %T "$1")
    case $fs in cifs|smb*|nfs*|fuseblk|fuse*|9p|v9fs) echo "  $1 在 $fs 上,不行,换本机磁盘"; return 1 ;; esac
    local free; free=$(df -BG --output=avail "$1" | tail -1 | tr -dc 0-9)
    (( free >= 40 )) || { echo "  $1 只剩 ${free}GB,不够 40GB"; return 1; }
}
ask_path "   工作目录?" /tmp/9008-work chk_work; W=$PATH_ANS

# ---------- 2 版本 ----------
say "2. 产物版本"
REL=$OLD_DIR/releases
latest=0
for d in "$REL"/V[0-9]* "$REL"/*_v[0-9]*; do
    [[ -d $d ]] || continue
    n=$(basename "$d"); n=${n#V}; n=${n%%[!0-9]*}; [[ $d == *_v[0-9]* ]] && { n=${d##*_v}; n=${n%%[!0-9]*}; }
    [[ $n =~ ^[0-9]+$ ]] && (( n > latest )) && latest=$n
done
(( latest )) || latest=${VERSION//[!0-9]/}
echo "  releases 里现有最新是 V$latest"
echo "  版本号随便写:数字、字母、. _ - 都行,如 110、110-beta、2.0-rc1(会放进产物文件名)。"
echo "  系统里"设置 → 版本号"显示的就是产物名(含你写的版本号)。里面第一串数字另外当作内部版本号 N(增量补丁名、刷机目录用);一个数字都没有就用 $((latest + 1))。"
while :; do
    read -r -p "  版本号 [默认 $((latest + 1))] " LABEL; LABEL=${LABEL:-$((latest + 1))}; LABEL=${LABEL#[vV]}
    [[ $LABEL =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && break; echo "  只能用字母数字 . _ -,且不能以符号开头"
done
if [[ $LABEL =~ ([0-9]+) ]]; then N=${BASH_REMATCH[1]}; else N=$((latest + 1)); fi
VERSION=V$N; VERSION_LABEL=$LABEL; export VERSION VERSION_LABEL
NOTE=; echo
while [[ -z $NOTE ]]; do read -r -p "  这版的更新说明(一句话,写进补丁包的说明,必填): " NOTE; done

# ---------- 3 相机 ----------
say "3. 相机(三选一)"
echo "   1) Pixel 相机    正常使用,没有微距(默认)"
echo "   2) 联想相机      能用微距,删掉了一些不可用功能"
echo "   3) 都不装        自己从商店装"
choose "   选哪个?" 1 1 2 3
case $CHOICE in 1) CAMERA=pixel ;; 2) CAMERA=zui ;; 3) CAMERA=none ;; esac

# ---------- 4 Google 精简 ----------
say "4. 精简 Google 应用的级别(都能从 Play 装回来)"
echo "   0) 不精简"
echo "   1) 只删冷门:YouTube 全家、Meet、Home、Wellbeing、Health、Tips、ARCore 等(默认)"
echo "   2) 再删日常:时钟、天气、计算器、日历、相册、Gmail、地图、录音机、TTS、Google 助理等"
echo "   3) 再删无障碍:TalkBack 等(需要读屏的别选)"
echo "   (级别太低镜像可能放不进固定分区,构建会报错,到时调高一级)"
choose "   选哪个级别?" 1 0 1 2 3
GOOGLE_SLIM=$CHOICE

# ---------- 5 可选功能 ----------
# 全局改机型用 optional/spoof/global-pif(运行时 resetprop + 挂载盖 build.prop),下面当普通可选功能问,
# 不单独开向导步骤(原来 optional/spoof/device-spoof 的 build/setprop/mount 三选一已删掉,和 global-pif 重复)。
mapfile -t ALLM < <(_sel_catalog)
OPT=(); DBG=()
for m in "${ALLM[@]}"; do case $m in optional/*) OPT+=("$m") ;; debug/*) DBG+=("$m") ;; esac; done
WITHS=()
say "5. 可选功能(${#OPT[@]} 个)"
echo "   每个回答 y/n,直接回车 = 括号里的默认;输入 a = 后面全按默认,s = 后面全不要。"
mode=ask
for m in "${OPT[@]}"; do
    [[ $mode == skip ]] && continue
    # 默认答案:这份 device.conf 的 MODS_OFF(设备自己的覆盖),或者补丁自己 patch.conf 的 DEFAULT=off——
    # 两边谁说 off 就 off,免得新补丁没来得及加进某个设备的 MODS_OFF 时,向导还按"默认装"问
    if _sel_in "$m" "${MODS_OFF[@]}" || [[ $(_sel_default "$m") == off ]]; then def=n; else def=y; fi
    if [[ $mode == default ]]; then [[ $def == y ]] && WITHS+=("$m"); continue; fi
    echo; echo "  ▸ $(title "$m")  ($m)"
    echo "    $(desc "$m")"
    r=$(risks "$m"); [[ -n $r ]] && echo "    ⚠ 可能的问题:$r"
    while :; do
        read -r -p "    要吗? [$([[ $def == y ]] && echo Y/n/a/s || echo y/N/a/s)] " a; a=${a:-$def}
        case ${a,,} in
            y|yes) WITHS+=("$m"); break ;;
            n|no) break ;;
            a) [[ $def == y ]] && WITHS+=("$m"); mode=default; break ;;
            s) mode=skip; break ;;
            *) echo "    请回答 y、n、a 或 s" ;;
        esac
    done
done

# ---------- 6 调试 ----------
if (( ${#DBG[@]} )); then
    say "7. 调试补丁(开机 ADB、免授权、adb root 等,正式版不要)"
    for m in "${DBG[@]}"; do echo "   - $(title "$m")  ($m)"; done
    ask "   要带上吗?" n && WITHS+=("${DBG[@]}")
fi

# ---------- 确认 ----------
OUT=$W/out; STOCK_ROOT=$W/stock
mkdir -p "$OUT"
PF=$OUT/wizard-profile.txt
{ echo "# ./make-9008.sh 生成;相机 CAMERA=$CAMERA,Google 精简 GOOGLE_SLIM=$GOOGLE_SLIM"
  echo -all; echo +required
  for m in "${WITHS[@]}"; do echo "+$m"; done; } > "$PF"
export CAMERA GOOGLE_SLIM PROFILE=$PF
unset WITH WITHOUT
select_resolve || { echo "选择有冲突,上面是原因" >&2; exit 1; }
mkdir -p "$REPO/out"; cp "$PF" "$REPO/out/wizard-last-profile.txt"
say "=================== 确认 ==================="
echo "产物版本:     $LABEL"
echo "更新说明:     $NOTE"
echo "原厂 9008 包: $STOCK_SRC"
echo "GSI 底包:     $GSI_SRC"
echo "工作目录:     $W"
echo "相机:         $CAMERA"
echo "Google 精简:  $GOOGLE_SLIM"
echo "共打 ${#SEL_MODS[@]} 个补丁,产物名后缀:$(select_flavor | sed 's/^$/(无,只有必选)/')"
for n in "${SEL_NOTES[@]}"; do echo "  依赖: $n"; done
echo "可选/调试补丁:"; (( ${#WITHS[@]} )) && printf '   %s\n' "${WITHS[@]}" || echo "   (无)"
echo "选择已存到 $PF"
echo "======================================================"
DO7Z=; ask "最后要不要把完整包再压成 7z?(多花十几分钟;发布时要,自己刷不用)" n && DO7Z=--7z
ask "开始?(解压 + 构建 + 出完整刷机包,要几十分钟)" y || { echo "没有动手。"; exit 0; }

# ---------- 准备输入 ----------
say "准备 GSI 底包"
GSI_IMG=
if [[ $GSI_SRC == *.img ]]; then GSI_IMG=$GSI_SRC
else
    GSI_IMG=$W/gsi/$(unzip -Z1 "$GSI_SRC" | grep '\.img$' | head -1)
    if [[ ! -f $GSI_IMG ]]; then echo "  解压 $GSI_SRC …"; mkdir -p "$W/gsi"; unzip -q -o "$GSI_SRC" -d "$W/gsi"; else echo "  已经解压过: $GSI_IMG"; fi
fi
echo "  核对 sha256 …"
got=$(sha256sum "$GSI_IMG" | cut -d' ' -f1)
[[ $got == "$BASE_GSI_SHA256" ]] || { echo "GSI 的 sha256 不对: $got(要 $BASE_GSI_SHA256)。补丁是对着这一版 GSI 写的,换了不能用" >&2; exit 1; }
export BASE_GSI=$GSI_IMG

say "准备原厂 9008 包"
if [[ -f $STOCK_SRC ]]; then
    if [[ -e $STOCK_ROOT/image/contents.xml ]]; then echo "  已经解压过: $STOCK_ROOT/image"
    else echo "  解压 $STOCK_SRC (约 8.7GB,要几分钟)…"; mkdir -p "$STOCK_ROOT"; 7z x -y -o"$STOCK_ROOT" "$STOCK_SRC" >/dev/null; fi
elif [[ -d $STOCK_SRC/image ]]; then STOCK_ROOT=$STOCK_SRC
else STOCK_ROOT=$(dirname "$STOCK_SRC"); fi
[[ -e $STOCK_ROOT/image/contents.xml ]] || { echo "解压后没找到 $STOCK_ROOT/image" >&2; exit 1; }
CARVED=$W/stock-carved
if [[ -f $CARVED/vendor.img && -f $CARVED/system.img ]]; then echo "  逻辑分区已经切过: $CARVED"
else
    echo "  从 super 分片切出 vendor / system 等逻辑分区 …"; mkdir -p "$CARVED"
    python3 "$TOOLKIT/flash9008/simsuper.py" "$STOCK_ROOT/image/rawprogram_save_persist_unsparse0.xml" "$CARVED" "$STOCK_ROOT/image" | tail -3   # 用原厂包自己的 XML(分片名是 super_N.img)
    [[ -f $CARVED/vendor.img ]] || { echo "没切出 vendor.img" >&2; exit 1; }
fi
unset FLASH9008_STOCK_DIRS   # conf 里它是数组,环境变量只能传字符串
export STOCK_DIR=$CARVED FLASH9008_STOCK_DIRS=$STOCK_ROOT/image

say "开始构建并打包"
exec "$TOOLKIT/build-9008.sh" "$CONF" "$OUT" --note "$NOTE" --profile "$PF" --full $DO7Z
