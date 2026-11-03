# herald-zygisk-fork-observer

## 做什么

rootless Zygisk 阶段 2:在真机上验证"ptrace 住 init(PID 1)、追踪它 fork+exec 出 zygote64 的那一刻、
在 zygote64 执行第一条指令之前读到 PC 和 ELF 入口地址完全一致"这条链路——这是将来要做的注入器最核心
的一步,先在真机上坐实,再谈往里面塞代码。

只做观察,不注入任何代码、不改 zygote 的任何行为、不新增 sepolicy。跟 `herald-zygisk-timing-probe`
(阶段 1,纯读 `/proc/uptime`)是同一条调研线的下一步,但这次是真的 `ptrace(2)` 系统调用,不是读文件。

算法和本机 x86_64 的 PoC(`monitor.c`,见早期研究笔记)完全一样,已经在开发机上拿严格的时间戳断言
验证过("目标进程的第一条指令确实是在被攥住之后才跑的,不是凑巧顺序对")。这次只是把同一套算法换成
ARM64 的寄存器结构(`user_pt_regs.pc` 代替 x86_64 的 `user_regs_struct.rip`),搬到真机上跑一次。

## 原理(大致)

- `src/observer.c`:静态编译的 aarch64 ELF(NDK `aarch64-linux-android21-clang -static -s`)。
  1. `PTRACE_SEIZE(1, PTRACE_O_TRACEFORK|PTRACE_O_TRACEEXEC)` 住 init,不设 `PTRACE_O_EXITKILL`
     ——万一这个程序自己崩了,内核会自动放行所有被跟踪的进程,不会把 init 或 zygote 卡死
     (ptrace(2) 文档里写的"跟踪器死了不带 EXITKILL 就自动放行"语义,不是我们自己保证的)。
  2. 等 init `fork()` 出新进程(`PTRACE_EVENT_FORK`),记一行日志,立刻 `PTRACE_CONT` 放行。
  3. 新进程 `execve()` 完成(`PTRACE_EVENT_EXEC`)——这一刻内存映像已经建好,但还没跑一条指令
     ——读 `/proc/pid/cmdline`,按固定参数 `--zygote` 认出是不是 zygote(这一刻它还没把自己改名
     成"zygote64",cmdline 还是 exec 时的原样,不能按名字猜)。
  4. 认出是目标就用 `PTRACE_GETREGSET`(`NT_PRSTATUS`)读 `user_pt_regs.pc`,和 `/proc/pid/exe`
     (这一刻已经指向新的可执行文件)的 ELF `e_entry` 字段比对,记一行日志,立刻 `PTRACE_CONT` 放行
     ——全程不停留,对 zygote 的影响理论上是零延迟。
  5. 拿到数据或者 10 秒超时,`PTRACE_DETACH` 全部跟踪对象,退出。
- `files/zygisk-fork-observer.rc`:`exec_start`(同步,照抄 `tango-guard.rc` 已经真机验证过的模式),
  挂在 `on post-fs-data`——比阶段 1 量出来的"到 zygote64 起来还有 880ms"这个窗口的起点早。
  `seclabel u:r:herald:s0`。
- `herald` 域本身是 `(typepermissive herald)`,而且已有 `CAP_SYS_PTRACE`(`init.herald.rc` 的
  capabilities 行)——**ptrace init 这一步不需要新增任何 sepolicy**:herald 是 permissive 域,
  只要是从 herald 发出的动作(包括 `ptrace`),SELinux 直接放行,不走 allow 规则判定。二进制直接以
  `herald_exec` 标签作为 service 入口,复用 `herald-core` 已经给 `herald_exec` 开过的 `entrypoint`
  权限,不用新加 file_contexts/sepolicy。

## 改动清单

- `etc/herald_payload/zygisk-fork-observer`(aarch64 静态二进制)、`etc/init/zygisk-fork-observer.rc`。

## 输入

无(二进制已经预编译好放在 `src/` 下,不依赖设备上的 Android NDK)。

## 依赖和顺序

`REQUIRES=(herald-core)`。实验性补丁,默认不打,量完就可以从 `device.conf` 的 `MODS` 里去掉。

## 换底包注意

和底包无关,`ptrace(2)`/`ELF` 都是标准 Linux ABI。

## 重新编译二进制

```bash
NDK=<你的 Android NDK 目录>/toolchains/llvm/prebuilt/linux-x86_64/bin
"$NDK/aarch64-linux-android21-clang" -O2 -Wall -static -s -o src/zygisk-fork-observer src/observer.c
```

## 验证

```bash
adb shell cat /metadata/herald_log/zygisk-fork-observer.log
```
预期类似:
```
[xxxx] start, attaching to init(1)
[xxxx] seized init
[xxxx] FORK from 1 -> 1234
[xxxx] EXEC pid=1234 cmdline="ueventd "
[xxxx] FORK from 1 -> 5678
[xxxx] EXEC pid=5678 cmdline="app_process64 -Xzygote /system/bin --zygote --start-system-server "
[xxxx] ZYGOTE pid=5678 pc=0x... elf_entry=0x... MATCH
[xxxx] detach 全部 N 个跟踪对象,退出
```
最后那行 `MATCH` 就是这次要验证的结论:真机上确实能在 zygote64 执行第一条指令之前精确截停它,
PC 和 ELF 入口完全一致——和本机 x86_64 PoC 的结论一样,只是这次是在真实设备、真实内核上跑的。
确认一下 `herald-start.log` 没受影响、开机时长没有明显变化。
