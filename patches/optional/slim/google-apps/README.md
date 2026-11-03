# slim/google-apps — Google 应用

可选。三份清单要一起用:`tts-voices` 删的是 GoogleTTS 应用的数据,应用本身在 `google-apps` 清单里删掉;留着 GoogleTTS 就别打本补丁。

| 清单 | 删什么 |
|---|---|
| [google-apps](lists/google-apps.md) | Google 预装应用(29 项) |
| [google-assistant](lists/google-assistant.md) | Google 助理和唤醒词录入 |
| [tts-voices](lists/tts-voices.md) | GoogleTTS 语音数据(78M;GoogleTTS 应用在 google-apps 清单里已删,数据成了孤儿) |

## 怎么维护

删什么由 `lists/*.list` 决定(一行一个路径,相对镜像里的 `system/`;`#` 注释;可以带通配符,版本号写成 `Xxx_*`);每份清单配一个同名 `.md` 讲为什么删。删不到的条目只记日志(`(没有) 路径`),日志末尾每份清单一行统计,换底包后看"底包里没有 N 项"的 N 变大了就去核对。通用脚本见 `toolkit/lib/removelist.sh`。
