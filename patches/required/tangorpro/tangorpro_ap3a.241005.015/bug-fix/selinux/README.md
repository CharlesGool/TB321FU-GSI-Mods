# selinux — 开机即 Enforcing

Mystic GSI 开机大半时间是 Permissive(permissiver 在后面才翻转),检测软件能看出来。这一类让 SELinux 从内核起就是 Enforcing,并补上 Enforcing 下排查问题要用的权限。

| 补丁 | 阶段 | 做什么 | 能不能单独关 |
|---|---|---|---|
| [enforce-at-init](fix/parts/001.enforce-at-init/) | system | 删 Mystic 的 permissiver,early-init 里 `setenforce 1` | 能,但会回到开机大半时间 Permissive |
| [kernel-enforcing](fix/parts/002.kernel-enforcing/) | 固件 | 内核命令行加 `enforcing=1 selinux=1`,内核从第一刻起就是 Enforcing(改 boot,登记给 [boot-assemble](../../../../general/boot-kernel/boot-assemble/) 落地) | 能,关了内核先 Permissive,靠 enforce-at-init 翻转 |
| `debug/shell-logcat` | system | Enforcing 下让 adb shell 能跑 logcat;调试用,已挪到 `patches/debug/`,默认不打 | 能(要抓日志时 `WITH=debug`) |

`enforce-at-init` 和 `kernel-enforcing` 配合才算完整:内核命令行带 `enforcing=1`,用户态不再有翻转。三个互相独立,顺序随意;别的 GSI 本来就 Enforcing 时会跳过。
