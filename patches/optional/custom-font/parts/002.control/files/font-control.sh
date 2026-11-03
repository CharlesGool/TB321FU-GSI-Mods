# custom-font/control 的 broker 插件(装在 /system/etc/herald_payload/plugins/font-control.sh,由 herald-start.sh source)。
# 字体包管理:包放在 /data/fonts/herald/packs/<名字>/(font_fallback.xml + 字体文件),当前用哪个写在 /data/fonts/herald/active。
# custom-font/hook 的 framework 钩子在 system_server 建字体表时读这两样,所以切换后要重启。用到 blog。
#   font [status]                      当前用的包、包数量、要不要重启、上次开机是否被自动撤回
#   font list                          所有包和各自是否完整
#   font install <zip 或目录> [名字]     装一个包(来源只能在 /data/local/tmp/、/sdcard/ 下)
#   font use <名字>                     选用(先检查文件齐全);重启生效
#   font reset                         回到系统字体;重启生效
#   font remove <名字>                  删包(正在用的不让删)
#   font check <名字>                   检查某个包:缺哪些文件
# 包的字体目录里没有的系统字体,use / install 时做成指向 /system/fonts、/product/fonts 的符号链接,这样 xml 里没改的字体照常能找到。
# 安全阀:开机脚本 herald-font.sh 发现上次选了包但开机没走完(没到 sys.boot_completed),就自动撤回,记在 reverted。
FT_ROOT=${HERALD_FONT_ROOT:-/data/fonts/herald}
FT_PACKS=$FT_ROOT/packs
FT_ACTIVE=$FT_ROOT/active
FT_BOOT=$FT_ROOT/boot_active
FT_REVERTED=$FT_ROOT/reverted
FT_STOCK=${HERALD_FONT_STOCK_DIRS:-"/system/fonts /product/fonts"}
FT_ROOTS=${HERALD_FONT_IMPORT_ROOTS:-"/data/local/tmp/ /sdcard/ /storage/emulated/0/"}
FT_MAX_KB=${HERALD_FONT_MAX_KB:-262144}                  # 单个包解开后的上限(KB)
FT_CHCON=${HERALD_FONT_CHCON:-chcon}
FT_UNZIP=${HERALD_FONT_UNZIP:-unzip}

herald_ft_nameok() { case "$1" in ""|*[!A-Za-z0-9._-]*|.*|*..*) return 1 ;; esac; [ "${#1}" -le 64 ]; }
herald_ft_ensure() { mkdir -p "$FT_PACKS" 2>/dev/null; chmod 0755 "$FT_ROOT" "$FT_PACKS" 2>/dev/null; $FT_CHCON -R -h u:object_r:font_data_file:s0 "$FT_ROOT" 2>/dev/null; return 0; }
herald_ft_active() { [ -f "$FT_ACTIVE" ] && tr -d '\r\n' < "$FT_ACTIVE"; return 0; }
herald_ft_refs() {                                        # 包里 xml 引用的字体文件名(去重)
  cat "$FT_PACKS/$1/font_fallback.xml" "$FT_PACKS/$1/fonts_customization.xml" 2>/dev/null \
    | grep -oE '[A-Za-z0-9_.+-]+\.(ttf|otf|ttc|otc)' | sort -u
}
herald_ft_link() {                                        # 系统字体里包没有的,做成符号链接
  for _fd in $FT_STOCK; do
    [ -d "$_fd" ] || continue
    for _ff in "$_fd"/*; do
      [ -f "$_ff" ] || continue
      _fb=${_ff##*/}
      [ -e "$FT_PACKS/$1/$_fb" ] || [ -L "$FT_PACKS/$1/$_fb" ] || ln -s "$_ff" "$FT_PACKS/$1/$_fb" 2>/dev/null
    done
  done
  return 0
}
herald_ft_missing() {                                     # 缺的文件名,空格分隔;xml 本身缺也算
  _fm=""
  [ -f "$FT_PACKS/$1/font_fallback.xml" ] || _fm="font_fallback.xml"
  for _fr in $(herald_ft_refs "$1"); do [ -e "$FT_PACKS/$1/$_fr" ] || _fm="$_fm $_fr"; done
  echo "${_fm# }"
}
herald_ft_reboot() {
  if [ -f "$FT_ACTIVE" ] && [ -f "$FT_BOOT" ]; then cmp -s "$FT_ACTIVE" "$FT_BOOT" && echo 0 || echo 1
  elif [ ! -f "$FT_ACTIVE" ] && [ ! -f "$FT_BOOT" ]; then echo 0
  else echo 1; fi
}
herald_ft_inroots() {                                     # 来源路径必须在允许的目录下、不含 ..
  case "$1" in *..*) return 1 ;; esac
  for _fr in $FT_ROOTS; do case "$1" in "$_fr"*) return 0 ;; esac; done
  return 1
}
herald_ft_prepare() {                                     # 补符号链接、打标签、查文件;缺文件时 FT_MISS 非空
  herald_ft_link "$1"
  $FT_CHCON -R -h u:object_r:font_data_file:s0 "$FT_PACKS/$1" 2>/dev/null
  FT_MISS=$(herald_ft_missing "$1")
}

heraldp_font_sub_status() {
  _fa=$(herald_ft_active); _fn=0
  if [ -d "$FT_PACKS" ]; then for _fp in "$FT_PACKS"/*; do [ -d "$_fp" ] && _fn=$((_fn + 1)); done; fi
  echo "ok 字体"
  echo "active=${_fa:-none}"
  echo "packs=$_fn"
  echo "reboot_required=$(herald_ft_reboot)"
  if [ -f "$FT_REVERTED" ]; then echo "reverted=$(tr -d '\r\n' < "$FT_REVERTED")"; fi
  echo "root=$FT_ROOT"
  return 0
}
heraldp_font_sub_list() {
  _fa=$(herald_ft_active)
  echo "ok font list"
  if [ -d "$FT_PACKS" ]; then
    for _fp in "$FT_PACKS"/*; do
      [ -d "$_fp" ] || continue
      _fn=${_fp##*/}
      _fm=$(herald_ft_missing "$_fn")
      _fv=yes; [ -n "$_fm" ] && _fv=no
      _fk=$(du -sk "$_fp" 2>/dev/null | cut -f1)
      _fx=0; [ "$_fn" = "$_fa" ] && _fx=1
      echo "pack=$_fn valid=$_fv active=$_fx kb=${_fk:-0}"
    done
  fi
  return 0
}
heraldp_font_sub_check() {
  herald_ft_nameok "${1:-}" || { echo "err 用法: font check <名字>"; return; }
  [ -d "$FT_PACKS/$1" ] || { echo "err 没有这个包: $1"; return; }
  _fm=$(herald_ft_missing "$1")
  if [ -z "$_fm" ]; then echo "ok $1 完整"; else echo "ok $1 不完整"; echo "missing=$_fm"; fi
}
heraldp_font_sub_use() {
  herald_ft_nameok "${1:-}" || { echo "err 用法: font use <名字>"; return; }
  [ -d "$FT_PACKS/$1" ] || { echo "err 没有这个包: $1"; return; }
  herald_ft_prepare "$1"
  [ -z "$FT_MISS" ] || { echo "err 包不完整,缺: $FT_MISS"; return; }
  echo "$1" > "$FT_ACTIVE.new" && mv -f "$FT_ACTIVE.new" "$FT_ACTIVE" || { echo "err 写 active 失败"; return; }
  rm -f "$FT_REVERTED"; blog "font: use $1"
  echo "ok font use $1 reboot-required"
}
heraldp_font_sub_reset() {
  if [ ! -f "$FT_ACTIVE" ]; then rm -f "$FT_REVERTED"; echo "ok font reset(本来就是系统字体)"; return; fi
  rm -f "$FT_ACTIVE" "$FT_REVERTED"; blog "font: reset"
  echo "ok font reset reboot-required"
}
heraldp_font_sub_remove() {
  herald_ft_nameok "${1:-}" || { echo "err 用法: font remove <名字>"; return; }
  [ -d "$FT_PACKS/$1" ] || { echo "ok font remove $1(本来就没有)"; return; }
  [ "$(herald_ft_active)" != "$1" ] || { echo "err $1 正在使用,先 font reset"; return; }
  rm -rf "${FT_PACKS:?}/${1:?}"; blog "font: remove $1"
  echo "ok font remove $1"
}
heraldp_font_sub_install() {
  _fsrc=${1:-}; _fname=${2:-}
  [ -n "$_fsrc" ] || { echo "err 用法: font install <zip 或目录> [名字]"; return; }
  herald_ft_inroots "$_fsrc" || { echo "err 来源只能在这些目录下(不含 ..): $FT_ROOTS"; return; }
  if [ -z "$_fname" ]; then _fname=${_fsrc##*/}; _fname=${_fname%.zip}; fi
  herald_ft_nameok "$_fname" || { echo "err 名字不合法(字母数字 . _ -,不超过 64): $_fname"; return; }
  [ "$(herald_ft_active)" != "$_fname" ] || { echo "err $_fname 正在使用,先 font reset"; return; }
  herald_ft_ensure
  _ftmp="$FT_PACKS/.tmp-$$"; rm -rf "${_ftmp:?}"; mkdir -p "$_ftmp" || { echo "err 建临时目录失败"; return; }
  if [ -d "$_fsrc" ]; then cp -R "$_fsrc"/. "$_ftmp"/ 2>/dev/null || { rm -rf "${_ftmp:?}"; echo "err 复制失败"; return; }
  elif [ -f "$_fsrc" ]; then $FT_UNZIP -o -q "$_fsrc" -d "$_ftmp" >/dev/null 2>&1 || { rm -rf "${_ftmp:?}"; echo "err 解压失败(不是 zip?)"; return; }
  else rm -rf "${_ftmp:?}"; echo "err 找不到: $_fsrc"; return; fi
  [ -f "$_ftmp/font_fallback.xml" ] || { rm -rf "${_ftmp:?}"; echo "err 包里没有 font_fallback.xml(要在顶层)"; return; }
  _fk=$(du -sk "$_ftmp" | cut -f1)
  [ "${_fk:-0}" -le "$FT_MAX_KB" ] || { rm -rf "${_ftmp:?}"; echo "err 包太大: ${_fk}KB,上限 ${FT_MAX_KB}KB"; return; }
  rm -rf "${FT_PACKS:?}/${_fname:?}"; mv "$_ftmp" "$FT_PACKS/$_fname" || { rm -rf "${_ftmp:?}"; echo "err 移动失败"; return; }
  herald_ft_prepare "$_fname"
  if [ -n "$FT_MISS" ]; then rm -rf "${FT_PACKS:?}/${_fname:?}"; echo "err 包不完整,缺: $FT_MISS"; return; fi
  blog "font: install $_fname"
  echo "ok font install $_fname(用 font use $_fname 选用)"
}

heraldp_cmd_font() {
  set -f; set -- $1; set +f
  _sub=${1:-status}; [ $# -gt 0 ] && shift
  case "$_sub" in *[!a-z0-9_]*|"") echo "err font 子命令只能是小写字母数字"; return ;; esac
  if type "heraldp_font_sub_$_sub" >/dev/null 2>&1; then "heraldp_font_sub_$_sub" "${1:-}" "${2:-}"
  else echo "err font 没有子命令 $_sub"; fi
}
