# slim/google-slim — 精简 Google 应用(分级)

放在 `required/tangorpro/tangorpro_ap3a.241005.015/` 下:应用目录名带版本号(如 `arcore-1.42`),换版本会变,所以按底包版本放。必选,用 `GOOGLE_SLIM` 选级别,默认 1。

| 级别 | 删什么 | 清单 |
|---|---|---|
| 0 | 不精简 | — |
| **1(默认)** | 不是人人都用的:YouTube / Kids / Music、Videos、图书、Meet、Home、Wellbeing、Health、Tips、ARCore、DevicePolicy、壁纸、位置记录(15 项) | [1-extras](lists/1-extras/google-extras.md) |
| 2 | 再加日常应用:计算器、日历、通讯录、拨号、短信、Drive、Keep、地图、相册、Gmail、时钟、TTS、录音机、天气(14 项),以及 Google 助理、GoogleTTS 语音数据、离线语音识别模型(92M,Live Caption / 离线语音输入可能用到) | [2-daily](lists/2-daily/daily-apps.md)、[google-assistant](lists/2-daily/google-assistant.md)、[tts-voices](lists/2-daily/tts-voices.md)、[offline-speech](lists/2-daily/offline-speech.md) |
| 3 | 再加无障碍:TalkBack、Switch Access、声音放大器、Voice Access、Scribe | [3-accessibility](lists/3-accessibility/accessibility.md) |

用法:`GOOGLE_SLIM=2 make 9008 NOTE="…"`。system 分区大小固定、余量很小,级别太低镜像可能放不进分区,构建会报错,调高一级即可。第 3 级会删读屏,需要读屏的用户不要选。

## 怎么维护

删什么由 `lists/<级别>/*.list` 决定(一行一个路径,相对镜像里的 `system/`;`#` 注释;可以带通配符,版本号写成 `Xxx_*`);每份清单配一个同名 `.md` 讲为什么删。删不到的条目只记日志,换底包后看"底包里没有 N 项"。

## 下拉栏磁贴

依赖被精简应用的磁贴(第 1 级:设备控制、钱包;第 2 级:闹钟)会一并从下拉栏默认列表和编辑页总表去掉,清单放在各级目录的 `*.tiles`,见 [1-extras/qs-tiles](lists/1-extras/qs-tiles.md)。
