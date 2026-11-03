# slim/accessibility — 无障碍应用

可选。**需要读屏的用户不要打**。

| 清单 | 删什么 |
|---|---|
| [accessibility](lists/accessibility.md) | 无障碍应用 |

## 怎么维护

删什么由 `lists/*.list` 决定(一行一个路径,相对镜像里的 `system/`;`#` 注释;可以带通配符,版本号写成 `Xxx_*`);每份清单配一个同名 `.md` 讲为什么删。删不到的条目只记日志(`(没有) 路径`),日志末尾每份清单一行统计,换底包后看"底包里没有 N 项"的 N 变大了就去核对。通用脚本见 `toolkit/lib/removelist.sh`。
