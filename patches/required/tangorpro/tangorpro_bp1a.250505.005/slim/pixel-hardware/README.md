# slim/pixel-hardware — 本机没有的 Pixel 硬件组件

放在 `required/tangorpro/tangorpro_bp1a.250505.005/` 下:只有 Pixel Tablet 的 GSI 才带这些组件,而且每个版本带的略有不同,所以按版本放;构建时底包 ID 以 `tangorpro_bp1a.250505.005` 开头才跑。别的版本的 GSI 复制一份到自己的版本文件夹再改清单。

| 清单 | 删什么 |
|---|---|
| [dock-hub](lists/dock-hub.md) | 底座 |
| [cast-display](lists/cast-display.md) | 投屏 |
| [retail-demo](lists/retail-demo.md) | 零售演示 |
| [tensor-services](lists/tensor-services.md) | Tensor 服务 |
| [side-fingerprint](lists/side-fingerprint.md) | 侧边指纹 |
| [uwb](lists/uwb.md) | UWB |
| [hbm-uv](lists/hbm-uv.md) | 强光/UV |
| [baseband](lists/baseband.md) | 基带 |
| [nfc](lists/nfc.md) | NFC 应用 |

## 怎么维护

删什么由 `lists/*.list` 决定(一行一个路径,相对镜像里的 `system/`;`#` 注释;可以带通配符,版本号写成 `Xxx_*`);每份清单配一个同名 `.md` 讲为什么删。删不到的条目只记日志(`(没有) 路径`),日志末尾每份清单一行统计,换底包后看"底包里没有 N 项"的 N 变大了就去核对。通用脚本见 `toolkit/lib/removelist.sh`。
