# emoji-font:用 EMOJI_FONT 覆盖 system/fonts/NotoColorEmoji.ttf,EMOJI_FLAGS_FONT 设了再覆盖 NotoColorEmojiFlags.ttf。
# font_fallback.xml 里两者都是 lang="und-Zsye" 的独立族(emoji 在前、国旗在后),按文件名引用、没有 postScriptName,
# 所以直接换文件即可,字体内部名字不一样也没关系。
need_input EMOJI_FONT
need_file fonts/NotoColorEmoji.ttf
chk() {
    local m; m=$(head -c4 "$1" | od -An -tx1 | tr -d ' \n')
    [[ $m == 00010000 || $m == 4f54544f ]] || die "$2 不是 TTF/OTF 字体(文件头 $m)"
}
chk "$EMOJI_FONT" EMOJI_FONT
put "$EMOJI_FONT" fonts/NotoColorEmoji.ttf 0644 0:0 u:object_r:system_file:s0
log "emoji 字体换成 $(basename "$EMOJI_FONT")"
if [[ -n ${EMOJI_FLAGS_FONT:-} ]]; then
    need_input EMOJI_FLAGS_FONT
    need_file fonts/NotoColorEmojiFlags.ttf
    chk "$EMOJI_FLAGS_FONT" EMOJI_FLAGS_FONT
    put "$EMOJI_FLAGS_FONT" fonts/NotoColorEmojiFlags.ttf 0644 0:0 u:object_r:system_file:s0
    log "国旗 emoji 字体换成 $(basename "$EMOJI_FLAGS_FONT")"
fi
