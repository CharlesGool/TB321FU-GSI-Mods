# attestation-fix — 密钥认证

## 做什么

接入 [herald-core](../../required/general/herald-core/) 的一个功能补丁:

- keystore2 attestation 伪造:用自带 keybox 签出 deviceLocked=true、verifiedBootState=green 的证书链。
- 指纹(PIF)profile 管理、本机 RKP 下发、keybox 导入导出、安全补丁日期同步。
- 命令:`heraldctl spoof get|list|apply|set|off|patch|mode|apps`、`heraldctl keybox …`、`heraldctl rkp …`(`spoof mode|apps` 转发给 spoof/app-spoof 的 broker 命令)。

**不靠 root**:引擎(keymint + inject)跑在核心的 `herald` SELinux 域里,inject 用 ptrace 注入 keystore2,全程不需要 KSU/Magisk/Zygisk。

## 怎么接入核心

- `plugins/00-attestation.sh`:broker 插件。`HERALDP_START` 起 keymint 和 inject 守护、种配置、boot-state 覆写;`heraldp_cmdf_*` 提供 get/set/disable/patch/list/apply/keybox_*/rkp_*;
  `HERALDP_SELFTEST` / `HERALDP_DIAG` 加自检和诊断段落;`HERALDP_ATTACH` 登记 `set`(profile JSON)和 `keybox_import`(base64)的附带数据。
  文件名带 `00-` 是为了先于 `app-spoof.sh` 加载(后者要用这里定义的 `CFG` `ENABLE_FLAG`)。
- `heraldctl.d/00-attestation.sh`:heraldctl 插件(`spoof` `keybox` `rkp`)。
- `sepolicy_attestation.cil`:keystore 域放行读 payload / 被回调 / 执行映射注入体,keystore 数据目录下 `bin` 的 type_transition。

## 原理(大致)

- `keymint`:常驻守护,注册 binder IRemotelyProvisionedComponent,维护 PIF 指纹、同步 security_patch,本机签发 RKP。配置基 `/data/misc/keystore/herald/`(二进制里硬编码)。
- `inject`:检测 keystore2 没被注入就 ptrace attach 进去,拦改 GMS 的 GetKeyEntry,用 keybox 伪造 attestation。注入后读 injector.log 确认 `committed … hook(s)` 才算成功,否则 kill keystore2 重注。
- 二进制首 boot 复制到可写的 `/data/misc/keystore/herald/bin`(type_transition 自动落 `herald_exec`),因为 inject 要把内嵌 payload .so 部署在自身目录,烤在只读 /system 部署不了。
- boot-state:late service(sleep 20 后)用 resetprop 覆写 verifiedbootstate/locked 等运行时属性(受 `global_pif_enabled` 标记门控,默认关)。
- 按 App 伪装模式下,keymint 每次启动前把 `ro.product.*` 临时设成 profile 值(设备 ID 登记),15 秒后改回真机值(V84–V95,详见 spoof/app-spoof)。
- keybox 自愈:之前历代版本(含改名前的 omk)都没有任何自动续签机制,keybox/RKP 全靠用户按
  `doc/herald-backend-api.md` 手动敲 `keybox`/`rkp` 命令(参考 `TB321FU_V63_后端操作测试表.md`),而且
  手动流程本身就很谨慎(先备份、一次只测一两个协议)。2026-11 加了后台自愈,但不是定时硬敲 Google 的
  RKP 服务器,而是:
  - 当前 keybox `--webui-get-keybox-state` 是 `"valid":true` 且 `--webui-check-keybox-revocation` 没查到
    `revoked` → 什么都不做。**已有一张能用的 keybox 时不会主动再去下发**——真机验证过,已有一张有效证书时
    再 `rkp_issue`(不管传 `v2` 还是别的协议)大概率被原生工作进程拒绝(`native RKP CSR rejected`,不同
    协议报的 status 还不一样),像是请求频率受限,反复敲只会浪费请求、可能被当滥用。
  - 只有当前 keybox 不是 valid 或者被吊销了,才动:先试一次 live 下发(`rkp_issue v2`)+ 导入,成功最好;
    失败就回退——把镜像里烤的 `seed/keybox.xml`(bundled)重新装一遍,至少不让设备停在"没有可用 keybox"
    的状态。bundled 这把若本身也被吊销了,这步救不了,得用户自己换一份新的 keybox.xml 手动
    `heraldctl keybox import`。
  - 检查间隔按连续失败次数退避(`$CFG/data/.rkp_fail_count`):没失败过(或刚自愈成功)30 分钟查一次,
    刚开始失败先快速重试几次(60 秒,最多 5 分钟),失败够多次退到 1 小时,一直失败退到 1 天——避免对着
    一个大概率修不好的状态一直按固定间隔硬敲。

## 改动清单

- `etc/herald_payload/`:`bin/{keymint,inject}`、`seed/*`、`plugins/00-attestation.sh`。
- `etc/heraldctl.d/00-attestation.sh`。
- `plat_sepolicy.cil` 追加 keystore 侧规则。

## 输入(device.conf)

| 变量 | 说明 |
|---|---|
| `HERALD_PAYLOAD` | 私有 payload 目录:`bin/{keymint,inject}` + `seed/{keybox.xml,injector.toml,config.toml,pif_fingerprint.json,vbmeta_state.toml}`(`bin/resetprop` 是核心的) |

## 依赖和顺序

要 `herald-core`。别的补丁依赖它:`spoof/global-pif`、`spoof/app-spoof`。

## 换底包注意

引擎二进制和底包无关(独立 ELF),换 GSI 底包不用动。inject 对 keystore2 的注入在不同安全补丁的 keystore2 上**可能**有差异,换固件后要在真机确认 `heraldctl selftest` 和 attestation 链正常。

## 踩过的坑

- V26:payload 放只读 /system 被 namespace 拒 → 挪可写目录;V26c 修 DAC;V26d 在 inject 循环里持续 chmod(keymint 启动会把自己数据目录 chmod 回 0700)。
- V27:三个引擎 bug(root 属主的 keymaster.db 触发 SQLite err14;pinned vb_key;inject 要确认 `committed hook(s)` 才算成功)。
- V33:`rkp-artifacts` 目录每次重启被 `chown -R` 带成 keystore 属主(它要求 root 私有)。
- V64:`spoof patch` 在 broker 里 keymint 找不到 resetprop,后端兜底(`via=backend`);list/apply 联网偶发 `unexpected end of file`,自动重试 2 次。
- V73:keymint 启动要同步 security_patch 属性,写不了就 fatal 无限重启 → 启动前先用自带 resetprop 对齐。
- V84–V95:按 App 伪装下 Play 认证 -66(设备 ID 登记成了真机)→ 属性窗口 + 读回确认。
- 2026-11:某些检测器把 `inject` 自带的"自动目标发现"(`auto_targets.rs`,监听/改写 `packages.list`、遍历 `/data/app` 找新装 App)
  当成 KernelSU 的 `track_throne` 判红;其余探测(内核、SELinux ksu 域、进程上下文、挂载命名空间、root 管理器)都是干净的,只有这一项。
  `injector.toml` 的 `scoop` 已经固定写了要伪装的包名,不靠自动发现也够用,所以每次注入成功后用 `inject --webui-set-auto-targets 0`
  关掉它(对已注入的 keystore2 生效的 IPC 命令,不是改配置文件;keystore2 重启、inject 重新注入后要再关一次,见注入守护循环)。
  未在真机复测过关掉之后检测器是否还会判红。
- 2026-11:keybox 自愈这段(见上面"原理")改过三轮,记一下走过的弯路:
  1. 最初做法是定时(每周)硬下发+导入,不管当前 keybox 好不好。真机一测,`rkp_issue` 不传 protocol 参数
     (等于 `auto`)直接被拒 `native RKP CSR rejected (status -20)`——一度怀疑是 attestation-engine 改名
     attestation-fix 弄坏了什么,查了二进制(没有任何 "omk" 字样)和 herald 域权限(从拆出来那天起就是
     `user root`,没变过),排除改名的可能。`doc/herald-backend-api.md` 记着 V63 的真机实测结论:**本机只有
     `v2`(和默认的 `auto`)能用,`v1`/`v1-native` 会报错**——改成写死 `v2` 再试,还是被拒,只是 status
     变成了 -18。说明不是协议选错,两种协议都走到了"原生工作进程拒绝 CSR"这一步,只是卡在了不同阶段。
  2. 查 `keybox state`/`inspector` 才发现:设备上同一时间已经有一张 `source:"google_remote"`、`valid:true`、
     没被吊销的 keybox,证书链才签发没几天(真机 ec 证书链有效期只约 12 天)。合理推断:**已有一张有效证书
     时再请求新的会被拒**,不是协议或改名的问题,是请求频率受限——这也解释了为什么"之前绝大部分版本都
     正常":那些版本(包括改名前的 omk)从来没有过自动续签机制,keybox/RKP 全靠用户按 V63 测试表手动敲,
     根本不会出现"已有效还硬请求"的情况。
  3. 用户提醒:哪张 keybox 不重要,能用、没被吊销就行,不一定非要等 Google 现场签发——于是改成现在这版:
     keybox 已经 valid 且未吊销就什么都不做;只有真的坏了才先试 live 下发,失败就回退重装 bundled
     `seed/keybox.xml`。bundled 这把如果本身也被吊销,这条路救不回来,只能用户自己换一份新 keybox.xml。
- 2026-11:一度怀疑"现场 RKP 下发只要设备处于全局伪装成 Pixel 状态就几乎必被拒",给自愈循环和手动
  `heraldctl rkp issue` 都加过"伪装状态门控"(检测到伪装就跳过现场下发)。后来用户用 V97(resetprop
  式全局伪装,`spoof/global-pif`)、以及把现在的引擎二进制换成 V97 版本,各做了一次真机对比实验:两次
  都是全局伪装成 Pixel、重启生效后现场 RKP 照样下发成功,Play 认证也过了——证明伪装状态本身跟 RKP
  成败**没有关系**,这个门控是基于错误假设做的,已经撤掉。真正会让现场 RKP 下发失败的是
  `spoof/device-spoof` 的 **build 模式**(build.prop 文件本身被真的改写成 Pixel,不是靠
  resetprop/挂载那种运行时伪装),补全这种模式漏写的属性之后问题依旧存在,具体卡在哪一层还没查清楚,
  但已确认跟伪装状态、跟哪颗引擎二进制都无关。

## 验证

```bash
adb shell heraldctl selftest          # 有 keymint=present
adb shell heraldctl spoof get
adb shell heraldctl keybox state
adb shell heraldctl spoof auto-targets get   # 确认已关:原始返回里是 0
adb shell heraldctl keybox state             # valid:true 且没被吊销就不用管,自愈循环也不会去动它
adb shell heraldctl keybox revocation
adb shell heraldctl diag                     # 不用 root:"== keybox 自愈" 段落有连续失败次数、keybox state/revocation/
                                              #   rkp list 原始结果、herald-start.log 里 RKP/keybox 相关的最后 20 行
                                              # (直接 cat /data/misc/keystore/herald/… 或 /metadata/herald_log/… 要 root,
                                              #   adb shell 默认是 shell 用户,读不了,报 Permission denied 是正常的)
```

### 默认身份(原 spoof/default-profile)

把镜像里预置的默认 profile(`/system/etc/herald_payload/seed/pif_fingerprint.json`)从烤进去的 **Pixel 7** 换成**本机的真实身份**:原厂固件的指纹、版本、补丁日期,`spoof_vending_build` 为 `false`。

TB321FU 上的结果:

```
{"version":2,"model":"TB321FU","product":"TB321FU","manufacturer":"Lenovo",
 "fingerprint":"qti/TB321FU/TB321FU:15/AQ3A.240912.001/ZUI_17.0.12.044_250612_ROW:user/release-keys",
 "brand":"Lenovo","device":"TB321FU","release":"15","id":"AQ3A.240912.001",
 "incremental":"TB321FU_ROW_OPEN_USER_Q00011.0_V_ZUI_17.0.12.044_ST_250612",
 "build_type":"user","tags":"release-keys","security_patch":"2025-05-05",
 "device_initial_sdk_int":34,"spoof_vending_build":false}
```

#### 原理

后端有两层互相独立的东西(详见 [`herald/README.md`](../../../../docs/topics/herald.md)):

- **全局属性伪装**(`spoof/global-pif`):开关打开时,按 profile 把 13 个 build 属性改掉。**默认关**。
- **keymint 认证引擎**:一直在跑。它伪造证书时用的设备身份来自 `config.toml` 的 `[device]` 段,本来就是 Lenovo / TB321FU(序列号也是本机的);证书里的补丁日期来自 `[trust]`,这是故意设成近期的,**本模块不碰**。

profile 因此只是"全局属性伪装"这一层的默认记录。以前它是 Pixel 7,带来两个问题:
- App 里"当前状态"、"Profile"一栏,伪装关着也显示 Pixel 7,容易误解成"现在伪装成了 Pixel 7";
- 用户没选过 profile 就把全局伪装打开,会被伪装成一台 Pixel 7,而不是原样。

换成本机真实身份之后,默认状态下后端存着的、系统实际显示的、认证引擎的设备身份三者一致;没选过 profile 就打开伪装等于不变。要伪装成别的机型,照旧用 `heraldctl spoof apply <机型>` 预填再 `spoof set`。

**不影响已有设置**:用户选过的 profile 存在设备上的 `/data/misc/keystore/herald/data/pif_fingerprint.json`,种子只在这个文件**不存在**时才拷过去(第一次开机,或清了数据)。所以刷新版本不会覆盖你已经选好的 profile,这个模块只改"新装/清数据后的默认状态"。想让已装的设备回到默认,把那个文件删掉再重启。

## 改动清单

- 用 `replace` 覆盖 `etc/herald_payload/seed/pif_fingerprint.json`(属主、权限、`herald_exec` 标签保持不变)。

## 输入(device.conf)

| 变量 | 说明 |
|---|---|
| `STOCK_SYSTEM_IMG`、`STOCK_VENDOR_IMG` | 原厂 system / vendor 镜像:读指纹、版本、补丁、`ro.product.first_api_level` |
| `ID_BRAND` `ID_DEVICE` `ID_MANUFACTURER` `ID_MODEL` `ID_NAME` | 和 `identity` 模块共用的机型字段 |

## 依赖和顺序

`require_mod required/general/herald-core`(它装种子目录),所以排在 `herald-core` 后面。属于控制后端这一组,是互不依赖规则的例外。不想用这个模块就把 `MODS` 里这一行注释掉,回到 `herald-core` 自带的私有种子(Pixel 7)。

## 换底包注意

字段全部从原厂固件现取;缺任何一个就失败(`make_profile.py` 会指出缺哪个 key),不会写出残缺的 profile。原厂 `system/build.prop` 常常没有裸的 `ro.build.fingerprint`,只有 `ro.system.build.fingerprint`,脚本两个都认。

## 踩过的坑

- 这是应用户提问加的:"为什么默认不伪装,下面也显示 Pixel 7 的信息"。V29 起的默认种子就是 Pixel 7,V61 已经把 App 的状态总览改成"关着伪装时不显示 keymint 里的 Pixel 7",但 Profile 表单仍然是用它预填的。

## 验证

新装(或删掉上面那个 profile 文件后重启):

```bash
adb shell heraldctl spoof get          # model 是 TB321FU,fingerprint 是 qti/TB321FU/…,最后一行 HERALD_GLOBAL_PIF_FLAG=off
adb shell getprop ro.product.model  # TB321FU
```
