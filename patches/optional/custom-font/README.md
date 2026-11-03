# font — 字体

> 一个补丁(`custom-font`),内部 2 个部分在 `parts/NNN.<部分>/`,按编号顺序跑,只能整个打或整个不打。依赖和说明见本目录的 `patch.conf`,每个部分的原理见它自己的 `README.md`。

> 一个补丁(`custom-font`),内部 2 个部分在 `parts/` 下按顺序跑。原来各是一个补丁,关联太紧合成一个(2026-11-01);依赖和说明见本目录的 `patch.conf`,每部分的原理见 `parts/<部分>/README.md`。

| 部分 | 做什么 | 形式 |
|---|---|---|
| [custom-font](parts/001.hook/) | 系统建字体表时改读 `/data/fonts/herald/` 里的字体包(没有字体包就原样) | 改 `framework.jar`(新 dex + `SystemFonts` 里一处钩子),不挂载、不占 system 空间,不依赖 herald |
| [font-control](parts/002.control/) | `heraldctl font …`:装包、选用、撤回、删除;开机保护(选了包但开机没走完自动撤回) | 免 root 核心插件 + init 一次性服务,依赖 `herald-core` |

字体包在电脑上用 [`toolkit/make-font-pack.py`](../../../toolkit/make-font-pack.py) 做:给它字体文件,它从系统原版 `font_fallback.xml` 改出配置,打成 zip。
