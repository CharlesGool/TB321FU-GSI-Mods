# font-replace — 换系统字体 / emoji(打包时直接替换文件)

| 补丁 | 做什么 | 输入 |
|---|---|---|
| [system-font](system-font/) | 用 `SYSTEM_FONT` 覆盖 `system/fonts/Roboto-Regular.ttf`(sans-serif / roboto 默认字体) | `SYSTEM_FONT`(默认 MiSans VF) |
| [emoji-font](emoji-font/) | 用 `EMOJI_FONT` / `EMOJI_FLAGS_FONT` 覆盖 `system/fonts/NotoColorEmoji.ttf` / `NotoColorEmojiFlags.ttf` | `EMOJI_FONT`(默认三星 emoji v16)、`EMOJI_FLAGS_FONT`(可不设) |

和 [custom-font](../custom-font/) 的区别:那个是运行时从 `/data/fonts/herald/` 读字体包、可撤回;这两个是打进 system,改不了只能重刷。
同时选了的话 custom-font 装的字体包优先(它在系统建字体表时整体换配置)。

字体文件不进仓库,放 DP11 项目 `inputs/fonts/`,路径在 `devices/<设备>/conf.d/fonts.conf`。
文件名不改、`font_fallback.xml` / `fonts.xml` 不改,所以要求:
- 系统字体最好是**可变字体(带 wght 轴)**:配置里 `Roboto-Regular.ttf` 声明了 `supportedAxes="wght,ital"`,不可变的字体粗体只能靠假粗体。
- 替换字体如果自带中文字形,中文也会走它(默认族排在 NotoSansCJK 前面)。
- Pixel 自己的界面(设置、桌面等)用 product 里的 Google Sans,拉丁字母不受影响,中文会落到默认族即新字体。
