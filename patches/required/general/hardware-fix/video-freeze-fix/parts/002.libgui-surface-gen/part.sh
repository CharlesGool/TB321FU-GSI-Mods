# system/lib64/libgui.so:Surface::disconnect() 里的 `mGenerationNumber = 0` 换成 NOP(A17 新增的行为,A16 及以前没有)。
# 底包的 libgui 没有这条指令(A15/A16)就跳过 —— 那些版本本来就没有这个问题,不是漏打。
python3 -I -c 'import elftools' 2>/dev/null || die "缺 python3 模块 pyelftools(apt install python3-pyelftools)"

LIB=lib64/libgui.so
TOOL=$MOD/patch_libgui_surface_gen.py
need_file "$LIB"
sudo cat "$SYS/$LIB" > "$WORK/libgui.orig.so"

st=$(python3 -I "$TOOL" --check "$WORK/libgui.orig.so") || die "libgui 分析失败(见上面的 ERROR)"
while IFS= read -r l; do log "$l"; done <<< "$st"
case $st in
    *未打补丁*)
        python3 -I "$TOOL" "$WORK/libgui.orig.so" "$WORK/libgui.so" | while IFS= read -r l; do log "$l"; done
        chk=$(python3 -I "$TOOL" --check "$WORK/libgui.so")
        [[ $chk == *没有清零\ generation* ]] || die "补丁版复查没报已打补丁:$chk"
        n=$( { cmp -l "$WORK/libgui.orig.so" "$WORK/libgui.so" || true; } | wc -l)   # cmp 有差异时退出码 1
        (( n >= 1 && n <= 4 )) || die "补丁版和原文件差了 $n 个字节,预期 1~4 个"
        replace "$WORK/libgui.so" "$LIB"
        ;;
    *没有清零*)
        log "跳过:这个底包的 Surface::disconnect 不清 generation(A16 及以前的 libgui),不需要这一部分"
        ;;
    *)
        die "libgui 状态异常,不改:$st"
        ;;
esac
