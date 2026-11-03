# 给 /vendor/lib 补上 32 位 GPU/gralloc 栈。原厂 vendor 的 lib/ 里只有 DSP 库(rfsa),32 位进程画不了界面。
# 文件放进 system/etc/vendor-lib32/,开机由 vendor-lib32.rc 用 overlay 盖到 /vendor/lib 上(见 README)。
need_input XIAOMI_LIB32_DIR
need_input STOCK_VENDOR_IMG
need_tool python3

# 1. 输入核对:目录里的文件集合和 sha256 必须与清单一致(多一个少一个都不行)
want=$(awk '{print $2}' "$MOD/manifest.sha256" | sort)
have=$(cd "$XIAOMI_LIB32_DIR" && find . -type f | sed 's|^\./||' | sort)
[[ $want == "$have" ]] || die "XIAOMI_LIB32_DIR($XIAOMI_LIB32_DIR)里的文件和 manifest.sha256 对不上:$(diff <(echo "$want") <(echo "$have") | head -5 | tr '\n' ' ')"
(cd "$XIAOMI_LIB32_DIR" && sha256sum -c --quiet "$MOD/manifest.sha256") || die "有文件的 sha256 和清单不一样,应该用小米 Eu OS3.0.304.0 的 vendor/lib"

# 2. 原厂 vendor 的 /lib 里不能已经有同名文件,不然 overlay 会改变原厂行为
m=$(mktemp -d -p "$WORK")
sudo mount -o loop,ro "$STOCK_VENDOR_IMG" "$m" || { rmdir "$m"; die "挂不上原厂 vendor 镜像 $STOCK_VENDOR_IMG"; }
cp_fc() { sudo cat "$m/etc/selinux/vendor_file_contexts" > "$WORK/vendor_file_contexts"; }
clash=""
while read -r _ rel; do sudo test -e "$m/lib/$rel" && clash="$clash $rel"; done < "$MOD/manifest.sha256"
if [[ -z $clash ]]; then cp_fc; fi
sudo umount "$m"; rmdir "$m"
[[ -z $clash ]] || die "原厂 vendor/lib 已有这些文件:$clash(32 位库已经存在?这个模块不适用)"

# 3. 标签:按 file_contexts 算(plat 的 + 原厂 vendor 的),32 位路径 /vendor/lib/... 套 lib(64)? 的规则
python3 -I "$MOD/label.py" "$XIAOMI_LIB32_DIR" "$SYS/etc/selinux/plat_file_contexts" "$WORK/vendor_file_contexts" > "$WORK/labels.tsv" \
    || die "有文件算不出标签(上面 NOLABEL 的行)"

# 4. 放进镜像
put_dir etc/vendor-lib32 0755 0:0 u:object_r:vendor_file:s0
# 先目录(浅的在前),再文件
while IFS=$'\t' read -r rel ctx; do
    if [[ -d $XIAOMI_LIB32_DIR/$rel ]]; then put_dir "etc/vendor-lib32/$rel" 0755 0:0 "$ctx"; fi
done < <(awk -F'\t' '{n=gsub("/","/",$1); print n"\t"$0}' "$WORK/labels.tsv" | sort -n | cut -f2-)
while IFS=$'\t' read -r rel ctx; do
    if [[ -f $XIAOMI_LIB32_DIR/$rel ]]; then put "$XIAOMI_LIB32_DIR/$rel" "etc/vendor-lib32/$rel" 0644 0:0 "$ctx"; fi
done < "$WORK/labels.tsv"
put "$MOD/files/vendor-lib32.rc" etc/init/vendor-lib32.rc 0644 0:0 u:object_r:system_file:s0
