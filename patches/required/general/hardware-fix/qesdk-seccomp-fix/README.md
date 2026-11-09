# qesdk-seccomp-fix:高通 qesdk 服务 seccomp 崩溃循环修复

适用于 TB321FU(SM8650,原厂 ZUI 17.0.12 高通 vendor)+ A17 GSI(DP11)。2026-11-09 在 DP11 user-v1.9 体检时发现。

## 现象

- `vendor.qesdk-securitymgr`、`vendor.qsap.qapeservice` 每 5 秒左右被 seccomp 杀一次(dmesg `received SIGSYS`),init 一直把它们标成 restarting。
- 两者日志都是 `libminijail[...]: blocked syscall: lseek`。
- 每次崩溃 init 都跑一次 `flags_health_check UPDATABLE_CRASHING`,白占 CPU 和待机功耗。用户层面没有可见异常(qesdk 是高通 Engine SDK,给部分游戏和性能接口用)。

## 原因

两个服务启动时用 minijail 套 seccomp 白名单(`/vendor/etc/seccomp_policy/qesdksec.policy`、`qsap_qapeservice.policy`),里面没有 `lseek`。
vendor 进程用的是系统 runtime APEX 里的 bionic,A17 的 libc 在这条路径上会调 `lseek`,A14 原厂不会。
同一 vendor 里 `qesdk-manager` 的 `qesdk.policy` 有 `lseek`,所以它一直正常。

## 修法

构建时从原厂 vendor 现取两份策略,在末尾追加 `files/*.add`,再用 vendor-bind 开机 bind 回 `/vendor`:

| 文件 | 追加 | vendor-bind 名 |
|---|---|---|
| `qesdksec.policy` | `lseek`;以及从 `qesdk.policy` 抄的退出/abort 路径 `exit exit_group rt_sigreturn restart_syscall getrlimit tgkill rt_tgsigqueueinfo` | `qesdk-secmgr-seccomp` |
| `qsap_qapeservice.policy` | `lseek`;abort 路径 `tgkill rt_tgsigqueueinfo` | `qsap-qape-seccomp` |

只追加,原有规则一行不改。原文件里已经有某个要追加的系统调用时构建直接报错(说明换了固件,要先核对)。
ZUI 17.0.12.044 上的结果:`qesdksec.policy` c071ae4c… → 8ba4a2a7…,`qsap_qapeservice.policy` 59053f38… → f0cc9e91…。
补丁文件标签 `vendor_configs_file`,和原文件一致。vendor-bind 在 post-fs 执行,比这两个服务启动早。

## 验证

```bash
adb shell 'ush -c "dmesg | grep vendor-bind"'        # 有 ok qesdk-secmgr-seccomp / ok qsap-qape-seccomp
adb shell getprop init.svc.vendor.qesdk-securitymgr  # running(之前是 restarting)
adb shell getprop init.svc.vendor.qsap.qapeservice   # running
adb logcat -d | grep -c 'blocked syscall'            # 0
```

DP11 test-v2.0-cust_bebug 上机验证(2026-11-09):两条 vendor-bind 都 ok,两个服务 running,`blocked syscall` 和 `UPDATABLE_CRASHING` 都是 0。

如果又报别的 `blocked syscall: xxx`,把 `xxx: 1` 追加进对应的 `.add` 即可。
