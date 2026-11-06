# system-font:用 SYSTEM_FONT 覆盖 system/fonts/Roboto-Regular.ttf。
# font_fallback.xml / fonts.xml 里 sans-serif、sans-serif-condensed、roboto 都指向这个文件名,文件名不变就不用改配置。
# 配置声明了 supportedAxes="wght,ital",替换字体带 wght 轴(可变字体)时各粗细档都正常。
need_input SYSTEM_FONT
need_file fonts/Roboto-Regular.ttf
magic=$(head -c4 "$SYSTEM_FONT" | od -An -tx1 | tr -d ' \n')
[[ $magic == 00010000 || $magic == 4f54544f ]] || die "SYSTEM_FONT 不是 TTF/OTF 字体(文件头 $magic)"
grep -qa 'fvar' <(head -c 4096 "$SYSTEM_FONT") || warn "SYSTEM_FONT 没有 fvar 表(不是可变字体),粗体会用假粗体"
put "$SYSTEM_FONT" fonts/Roboto-Regular.ttf 0644 0:0 u:object_r:system_file:s0
log "系统字体换成 $(basename "$SYSTEM_FONT")($(( $(stat -c%s "$SYSTEM_FONT") / 1024 / 1024 ))MB)"
