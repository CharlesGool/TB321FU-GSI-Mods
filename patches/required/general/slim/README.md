# slim — 精简

只删东西的补丁都在这里。system 分区大小固定、余量很小,删掉用不上的才放得下新功能。

**精简脚本是通用的**(`toolkit/lib/removelist.sh` 的 `slim_apply`),**删什么由各个补丁自己决定**:补丁文件夹里的 `lists/*.list` 就是它的精简清单(一行一个路径,相对 `system/`,可带通配符 `Xxx_*`),`apply.sh` 只有两行调用脚本。适用范围由补丁所在文件夹决定(`required/tangorpro/tangorpro_ap3a.241005.015/…` 只在底包 ID 命中时才跑)。每个 Pixel GSI 版本的组件、应用目录名都略有区别,所以 Pixel 相关的精简补丁按版本放;换版本就复制一份到新版本文件夹再改清单。

| 补丁 | 删什么 | 默认 |
|---|---|---|
| [slim/old-vndk](old-vndk/) | 只留 vendor 要用的 VNDK apex,删其余版本(~246M;脚本,按原厂 vendor 现算,和哪个 GSI 无关,所以留在 general) | 打 |
| [slim/pixel-leftovers](../../tangorpro/tangorpro_ap3a.241005.015/slim/pixel-leftovers/)(在 `required/tangorpro/tangorpro_ap3a.241005.015/` 下) | Pixel 专属但本机用不上的应用和数据:Play 自动安装配置、"正在播放"库、Pixel 相机、儿童模式(4 份清单) | 打 |
| [slim/pixel-hardware](../../tangorpro/tangorpro_ap3a.241005.015/slim/pixel-hardware/)(同上) | 本机没有对应硬件的 Pixel 组件:底座、投屏、零售演示、Tensor 服务、侧边指纹、UWB、强光/UV、基带、NFC(9 份清单) | 打 |
| [slim/gsi-traces](../../tangorpro/tangorpro_ap3a.241005.015/slim/gsi-traces/)(同上) | GSI 制作工具(Mystic、phh-treble)留下的调试件和别的机型的兼容件(5 个部分) | 打 |
| [slim/google-slim](../../tangorpro/tangorpro_ap3a.241005.015/slim/google-slim/)(同上) | Google 应用分级精简(`GOOGLE_SLIM`):1 冷门(默认)、2 加日常应用/助理/TTS 数据/离线语音模型、3 加无障碍(TalkBack),0 不精简(3 级清单) | 打 |

