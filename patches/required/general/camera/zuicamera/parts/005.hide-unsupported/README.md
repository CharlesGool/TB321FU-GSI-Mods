# zuicamera/hide-unsupported — 屏蔽依赖缺失组件的相机功能

## 做什么

联想相机有几处功能要靠原厂系统里的其他组件,本系统没有。逐个查过反编译代码后,只有下面这些会露出入口却用不了,这个模块把它们屏蔽掉:

| 功能 | 依赖 | 本系统的表现 | 处理 |
|---|---|---|---|
| 互联录制(模式栏 id 29) | 联想互联服务 `com.zui.wifip2p` | 入口在,用不了 | 从 TB321FU 的模式栏 `modules-id` 去掉,同时去掉 `INTERCONNECT_RECORD` feature |
| 微距(模式栏 id 6) | 2 号相机(`kirby_lce_sc202cs_macro`) | 不开 `macro-camera-fix` 时 HAL 处于 GSI 模式,只报 0、1 号相机 | 那个模块没开时从模式栏去掉;开了(要排在本模块前面)就保留 |
| 许可协议 / 隐私政策链接(首次权限弹窗、设置页) | `com.lenovo.lenovoprivacy` | `DialogHelper.jumpToLenovoLegalInfo` 直接 `startActivity`,没有 try,点了就闪退 | 包一层 try/catch,找不到页面就不动 |

TB321FU 的模式栏原来是 `29,1,0,24,6`(互联录制、录像、拍照、扫描、微距),改完是 `1,0,24`;开着 `macro-camera-fix` 时是 `1,0,24,6`。

应用自己已经会先检查依赖、不用改的:语音拍照(先查 `com.lenovo.menu_assistant` 装没装)、AI 识图(先查 `com.zui.ai.lens`)、点缩略图看照片(ZUI 相册 → Google 相册 → 系统里任意能打开图片的应用,依次回落)。

## 做法

用 `toolkit/lib/apk-smali.sh` 跑 `files/patch_hide.py`:
- `raw/app_features`(资源名被混淆,按内容找到 `res/*.json` 里带 `modules-id` 的那份)按文本改,文件里有 `//` 注释,不能当标准 JSON 解析再写回;
- `DialogHelper.smali` 加 try/catch。

只换 `classes2.dex` 和这一个 raw 资源文件,`resources.arsc` 不动,APK 重签。

## 微距什么时候保留

`apply.sh` 用 `mod_ran required/general/hardware-fix/macro-camera-fix` 看:那个模块跑过(HAL 按原厂模式报 2 号相机)就传 `HIDE_KEEP_MACRO=1`,`patch_hide.py` 不去掉 6。

## 依赖

`require_mod zuicamera/app`;和 `camera-id-check`、`real-device-id` 互不依赖,顺序随意。需要 `java`、`zipalign`、`apksigner`、`python3`、`openssl`、`unzip` 和 `APKTOOL_JAR`。

## 验证

打开联想相机,模式栏只有"录像 / 拍照 / 扫描";进设置点"许可协议""隐私政策"不闪退(什么都不发生)。

## V82:OCR 按钮
取景界面的 OCR 按钮点了就闪退。应用逻辑:`ro.config.zui.region` 不是 ROW(本系统没有这个属性)且配置里有 `OCR`/`OCR_AILENS` 时显示 OCR 按钮,点了走应用自带的联想 OCR 算法(`lcaf/ocr/OcrAlgorithm`、Dolphin SDK),本系统跑不起来;ROW 区域显示的是 Google Lens 按钮。补丁把 TB321FU 条目里的 `OCR_AILENS` 去掉,按钮不再显示。**没上真机**,闪退的确切原因没抓日志。

## 设置页去掉水印和 OCR(2026-11-01)

`patch_hide.py` 第 3 段:联想相机设置页 `CameraSettingsFragment.filterFrontBackCameraSetting` 里本来有"满足条件就 `recursiveDelete` 这个选项"的分支,
OCR 的条件是 `isAilensEnabled || isRow`,水印的条件是 `isPrcCommercial || LGSI_MODE || AOSP_MODE`。这里把两处的"不满足就跳过删除"的 `if-eqz` 去掉,一律删除。
水印要相机 HAL 认出联想相机才生效,而 zuicamera 不再强行设 HAL 客户端属性(会影响别的相机应用);OCR 本系统跑不起来(模式栏上的 OCR 按钮早就去掉了)。
`setSummary2(findPreference(...))` 对 null 有保护,选项被删后不会崩。
