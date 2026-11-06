# emoji-font — 替换 emoji 字体

打包时用 `EMOJI_FONT` 覆盖 `system/fonts/NotoColorEmoji.ttf`;`EMOJI_FLAGS_FONT` 设了再覆盖 `NotoColorEmojiFlags.ttf`(不设就保留底包的国旗字体)。
默认是 KLCOS 时期那套:三星 emoji(build 20241021_v16)+ Noto 国旗 2021-10-13,文件在 DP11 项目 `inputs/fonts/`,路径见 `conf.d/fonts.conf`。

- 字体配置按文件名引用、没有 postScriptName,所以不改配置。
- 替换字体没有的新 emoji 会往后找国旗/符号字体,再没有就是方框。
- Google Play 系统更新如果往 `/data/fonts` 下发新版 emoji,会盖过这里的替换。
