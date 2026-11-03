# spoof — 机型伪装

挂在 [herald-core](../../required/general/herald-core/)(免 root 后端)上的伪装:给检测/风控应用看的机型身份。两个都 `REQUIRES=(attestation-fix)`,选了会自动带上它。

| 补丁 | 做什么 | 运行时开关 |
|---|---|---|
| [global-pif](global-pif/) | 全局指纹伪装:开机早期用 resetprop 改 `ro.product.*`,挂载盖一份改过的 build.prop 让文件和属性一致 | `heraldctl spoof set\|off` |
| [app-spoof](app-spoof/) | 按 App 伪装(默认模式):系统属性不动,只对名单里的 App 改 `Build.*`;改 framework.jar,要排在 [stale-boot-image](../../required/general/boot-kernel/stale-boot-image/) 前面 | `heraldctl spoofmode app\|global` |

原来还有一个 `device-spoof`(打包时直接改 build.prop / 开机 setprop / setprop 加挂载盖三选一),和
`global-pif` 功能重复(挂载这种做法 `global-pif` 自己就有),已经删掉,只留 `global-pif` 这一条线。

全局伪装下联想相机会读到假机型而闪退,[zuicamera/real-device-id](../zuicamera/parts/004.real-device-id/) 解决这个。
