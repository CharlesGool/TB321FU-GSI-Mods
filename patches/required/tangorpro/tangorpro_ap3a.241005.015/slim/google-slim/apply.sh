# slim/google-slim:按 GOOGLE_SLIM 分级精简 Google 应用。每级一个 lists/ 子目录,级别越高包含前面所有级。
#   0 不精简   1(默认)冷门应用   2 再加日常应用、Google 助理、TTS 语音数据、离线语音模型   3 再加无障碍(TalkBack 等)
# 精简脚本是通用的(toolkit/lib/removelist.sh 的 slim_apply),删什么由 lists/ 下各级的 .list 决定。
# 每级目录里的 *.tiles 是"下拉栏磁贴 依赖路径":依赖的应用被这一级(或更低级)精简掉了,就把磁贴从默认列表里去掉。
source "$TOOLKIT/lib/removelist.sh"
level=${GOOGLE_SLIM:-1}
[[ $level =~ ^[0-3]$ ]] || die "GOOGLE_SLIM 只能是 0、1、2、3,现在是 '$level'"
log "Google 精简级别: $level"
(( level == 0 )) && exit 0
tile_files=()
for d in "$MOD"/lists/[1-3]-*; do
    n=${d##*/}; n=${n%%-*}
    (( n <= level )) || continue
    slim_apply "$d"
    for f in "$d"/*.tiles; do [[ -f $f ]] && tile_files+=("$f"); done
done

# 磁贴:SystemUI 有两张表——quick_settings_tiles_default(下拉栏默认显示的)和 quick_settings_tiles_stock(编辑页"可添加"区的内置总表),
# 值分别放在 tiles.default 和 tiles.stock(底包 SystemUITitan 的原值)。按已应用各级的 *.tiles 检查每个磁贴依赖的路径是否还在 $SYS 里,
# 缺的从两张表里都去掉,用静态 RRO 覆盖(优先级比底包自带的 Titan RRO 高)。
(( ${#tile_files[@]} )) || exit 0
tiles=$(grep -v '^#' "$MOD/tiles.default" | head -1 | tr -d '[:space:]')
stock=$(grep -v '^#' "$MOD/tiles.stock" | head -1 | tr -d '[:space:]')
[[ -n $tiles && -n $stock ]] || die "$MOD/tiles.default 或 tiles.stock 里没有磁贴列表"
drop=()
while read -r tile path _; do
    [[ -z $tile || $tile == '#'* ]] && continue
    # 路径可以带通配符(应用目录名带版本号,如 Xxx_*)
    if sudo bash -c 'cd "$1" && compgen -G "$2" >/dev/null' _ "$SYS" "$path"; then continue; fi
    drop+=("$tile")
done < <(sed 's/#.*//' "${tile_files[@]}")
if (( ${#drop[@]} == 0 )); then log "没有失效磁贴,不改"; exit 0; fi
drop_tiles() {   # $1 = 逗号分隔的磁贴表,去掉 drop 里的
    local l=$1 t
    for t in "${drop[@]}"; do
        l=$(awk -v t="$t" 'BEGIN{RS=","; ORS=""; first=1} { sub(/\n$/,""); if ($0 != t) { if (!first) printf ","; printf "%s", $0; first=0 } }' <<< "$l")
    done
    printf '%s' "$l"
}
new=$(drop_tiles "$tiles"); new_stock=$(drop_tiles "$stock")
log "去掉磁贴: ${drop[*]}"; log "新默认列表: $new"; log "新内置总表: $new_stock"
src=$WORK/src; mkdir -p "$src/res/values"
cat > "$src/AndroidManifest.xml" <<M
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.herald.overlay.qstilesclean">
    <application android:extractNativeLibs="false" android:hasCode="false"/>
    <overlay android:isStatic="true" android:priority="322" android:targetPackage="com.android.systemui"/>
</manifest>
M
cat > "$src/res/values/values.xml" <<V
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="quick_settings_tiles_default" translatable="false">$new</string>
    <string name="quick_settings_tiles_stock" translatable="false">$new_stock</string>
</resources>
V
"$TOOLKIT/lib/build-rro.sh" "$src" "$WORK/qs-tiles-clean.apk" 1 >/dev/null
put "$WORK/qs-tiles-clean.apk" product/overlay/herald-qs-tiles-clean.apk 0644 0:0 u:object_r:system_file:s0
