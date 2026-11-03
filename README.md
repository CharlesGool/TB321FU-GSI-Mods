# TB321FU-GSI-Mods

[English](docs/en/README.md) · [Español](docs/es/README.md) · 简体中文

联想拯救者 Y700 三代(TB321FU)上跑 Pixel GSI 的全部改动。**一个小补丁一个文件夹**,每个补丁自带身份文件、原理文档和应用脚本,互不依赖(依赖都写明了,构建时自动处理),想要哪个打哪个。

本仓库放在 GSI 工程 `tb321fu_pixelos_15_tangorpro_ap3a.241005.015/` 里面(工程里很多东西是专为这个底包做的)。它是 V1–V66 那套手工流程的重整版:同样的改动,但从"每版直接改上一版的文件树"改成**从原始材料一条命令重新构建**。工程目录怎么分见上一级的 `README.md`。

## 怎么构建

刷机包 = 原始材料 + 依次 apply 选中的补丁 + 打包:

```
GSI 底包 ──apply system 补丁──→ system 镜像 + vbmeta_system ─┐
原厂 boot ─apply 固件补丁────→ boot 集(boot/vbmeta/…)  ─────┼─→ 9008 保数据刷机包(7z)
原厂 9008 包 ──────────────────────────────────────────────┘
```

```bash
make list                           # 看全部补丁和这次打哪些
make build                          # 出 system 镜像 + vbmeta_system + boot 集,在 out/tb321fu-a15/
make 9008 NOTE="版本备注"           # 三步一起:system + boot 集 + 9008 包,输出在 out/tb321fu-a15/
```

`make build` 就是 `toolkit/build.sh`:GSI 底包和原厂固件放进同一个工作区,按一张清单依次打补丁(改 system 的改树,改 boot 的出 boot.img,两边都改的一次改完),最后统一打包。`make 9008` 是 `toolkit/build-9008.sh`:build 之后接 `toolkit/flash9008/make_9008_patch.sh`。9008 包的细节见 [docs/FLASH-9008.md](docs/FLASH-9008.md),AVB 重签见 [docs/AVB-RESIGN.md](docs/AVB-RESIGN.md)。

## 选补丁

不用改 `device.conf`。构建时加选择规则,system、boot 集、9008 包三步用同一份:

```bash
make 9008 WITHOUT=tango NOTE="不带 32 位"                     # 去掉一整类
make build WITHOUT=refresh-control,hotspot-6ghz-unlock                   # 去掉几个
make build WITH=optional/refresh-auto-switch                  # 加上默认不打的
make 9008 WITH=app-backup,custom-font NOTE="…"               # 加上默认不打的高级功能
make 9008 PROFILE=no-tango NOTE="…"                            # 用预设
make menu SAVE=my-build                                        # 勾选菜单,存成预设 my-build
make info P=battery                                            # 看一个补丁依赖谁、谁依赖它
```

规则写法:补丁名(`battery`、`brightness/hbm-unlimited`)、大类文件夹(`slim`、`brightness`)、通配(`hotspot-*`、`spoof/*`)、`all`。

- **默认**:`device.conf` 的 `MODS` 是本设备全部可选补丁(改 system 的、改 boot 的都在里面)(也定了执行顺序),去掉 `MODS_OFF` 里的就是默认选择。
- **默认不打的**:高级 / 非原生功能(`app-backup`、`custom-font`、`devopts-hide/*`、`statusbar-netspeed`、`game-mode`、`perf/*`、`herald-readonly-shell`、`herald-rooted-shell`)、非常规修改(`brightness/hbm-unlimited`)、调研和诊断用的。要的话 `WITH=` 加上。
- **预设**:`devices/<设备>/profiles/<名字>.txt`,一行一条 `+规则` / `-规则`,`-all` 表示从头挑。现有:`no-tango`、`no-herald`、`slim-only`。
- **依赖自动处理**:选了一个补丁,它 `patch.conf` 里 `REQUIRES` 的会自动带上,`WANTS` 的也顺带打上(软依赖,例:改 jar 的补丁带上 `stale-boot-image`);往某个产物登记改动的(Wi-Fi APEX、boot),会自动带上负责打包它的 assemble 补丁。被你明确去掉的不会被带回来,依赖它的补丁跟着去掉。构建开头会把这些全列出来。
- **顺序**:永远按 `MODS` 里的顺序跑;构建前按各补丁 `patch.conf` 的 `REQUIRES`/`AFTER`/`BEFORE` 核对这个顺序。
- 每次构建的选择记在输出目录的 `SELECTION.txt`;打 9008 包时会核对 system 和 boot 集是不是同一份选择做的。

## 一个补丁长什么样

```
patches/optional/brightness/hbm-unlimited/      普通补丁
  patch.conf   身份:名字、一句话说明、阶段、依赖、顺序要求、运行时开关(选补丁和检查都读它)
  README.md    原理:为什么改、改了哪里、输入、换底包注意、踩过的坑、怎么验证
  apply.sh     在工作树上做改动
  files/ src/ patches/   原样放进镜像的文件 / 源码和构建脚本 / 对底包打的补丁

patches/required/general/hardware-fix/bluetooth-fix/                 合并补丁:几个部分修的是同一件事或关联太紧,只能整个打或整个不打
  patch.conf   同上
  README.md    整体说明和部分表
  apply.sh     外部依赖 + run_parts(按编号顺序跑各部分,每部分在自己的子 shell 里)
  parts/001.profile-props/        part.sh + README.md + files/…   每个部分自己的实现和原理
  parts/002.a2dp-offload-policy/
  parts/003.sco-call-fix/
```

`patch.conf` 管"它是谁、和谁有关系",README 管"它怎么实现的"。写法和规则见 [docs/MODULE-SPEC.md](docs/MODULE-SPEC.md)。

## 补丁一览

全部 47 个补丁(默认打 31 个,含自动带上的 1 个)的表在 **[patches/README.md](patches/README.md)**,按 `required/general`(必须打·通用修复)、`required/tangorpro` 等(必须打·特定底包限定,文件夹名是底包 ID 前缀,命中才跑)、`optional`(可选)、`debug`(调试)分表,由 `toolkit/gen-index.sh` 从各 `patch.conf` 生成,带编号和中文名。按用途看(★ = 默认不打):

| 用途 | 补丁 |
|---|---|
| 精简(只删东西) | `slim/pixel-leftovers`、`slim/old-vndk`、`slim/pixel-hardware`(Pixel Tablet 专属)、`slim/google-slim`(Google 应用分级精简)(通用脚本 + 各补丁自带 lists/)、`slim/gsi-traces`(Mystic/phh 留下的) |
| 机型还原 / 去痕迹 | `identity`、`debug-off`、`gsi-hide`、`rw-system-tmpfs`、`kernel-builder-string`(改 boot) |
| SELinux | `selinux/fix`(SELinux 修复,system 和 boot 一起改)、`selinux/shell-logcat` |
| 修 GSI 的毛病 / 还原原厂 | `auto-brightness-fix`(自动亮度修复)、`rotation-fix`、`bluetooth-fix`、`hotspot-ui-fix`、`build-consistency-dialog-fix`、`macro-camera-fix` |
| 原厂功能 | `zuicamera`(联想相机)、`faceunlock`(人脸解锁)、`battery`(电池保护/上限/旁路)、`6ghz-fix`(国家码 + 6GHz 频段修复,必选)、`hotspot-control`(热点自定义 + 命令,可选)、`wifi-apex-assemble`(APEX 打包)、`hotspot-6ghz-unlock` |
| 免 root 核心和伪装 | `herald-core`(核心:命令通道、配对、插件接口)、`attestation-fix`(密钥认证:keymint 引擎 + 默认身份,接入核心)、★`spoof/global-pif`、★`spoof/app-spoof`、★`herald-readonly-shell` |
| 系统功能 | `navbar-hide`、`adaptive-refresh-fix`(自适应刷新率修复)、`refresh-control`(刷新率控制)、★`refresh-auto-switch`(按应用/电量自动换)、`tango`(32 位 APK) |
| 高级功能(都 ★) | `app-backup`、`custom-font`、`devopts-hide`、`statusbar-netspeed`、`game-mode`、`perf`(性能调节)、`perf-game-boost` |
| 非常规 | ★`brightness/hbm-unlimited` |
| 收尾 / 打包 | ★`stale-boot-image`(选了改 jar 的补丁会自动带上)、`boot-assemble`(写 boot.img) |
| 调试 / 调研 / 诊断(`debug/`,默认都不打) | `debug/shell-logcat`、`debug/adb-on-boot`、`debug/rooted-adbd`、`debug/diag-boot-camera-log`、`debug/herald-readonly-shell`、`debug/herald-rooted-shell`、`debug/herald-zygisk-timing-probe`、`debug/herald-zygisk-fork-observer`;偏调试的 ★`overlay-idmap-reset` 留在 optional |

分法:修同一件事、合起来才完整的合成一个补丁(内部 `parts/001.xxx` …);能各自起作用、用户可能只要其中一个的分开;"名字沾边"不算一类(热点入口 UI 和热点行为分开,亮度和刷新率分开);非常规的修改单独成补丁。

## 换底包

换 GSI 来源或安卓版本(比如 Pixel Fold 的安卓 16 GSI)时,先摸底:

```bash
make survey BASE_GSI=/路径/新底包.img      # 每个补丁在新底包上单独跑一遍(要 sudo,慢)
```

输出 `out/survey-<底包名>/report.md`:每个补丁能用 / 不能用(附补丁自己报的原因)/ 因为依赖不能用;还有一份去掉不能用项的建议预设 `profile.txt`。看过之后拷到 `devices/<设备>/profiles/` 就能 `PROFILE=` 用,再逐个修不能用的。

为什么摸底结果可信:补丁都按"先检查前提,不满足就报错说明原因"写,不会悄悄少打;删除类补丁遇到底包里本来就没有的东西只记一行日志、不算失败。最容易受影响的是改 jar / APEX 的 smali 补丁(人脸、Wi-Fi、伪装、字体、网速、按 App 隐藏…),换安卓大版本通常要对照新底包重做补丁。固件阶段的补丁只跟原厂固件有关,换 GSI 不影响。能跑过但功能不对的(比如属性名在新版本里改了)还得上真机看。

## 测试

```bash
make unit                                  # broker/heraldctl 插件的单元测试(不碰真机、不要 root)
toolkit/tests/test-patch-meta.sh           # 每个补丁的 patch.conf 和 apply.sh 对得上、顺序对、总表是最新的
make test                                  # 每个补丁单独在干净底包上跑一遍(要 sudo)
toolkit/tests/test-modules.sh devices/tb321fu-a15/device.conf --leave-out   # 每个补丁各去掉一次,跑剩下的全部
```

`test-modules.sh` 在只读挂载的底包上叠 overlayfs,每个测试都是干净底包,不复制几个 GB。

## 目录

| 目录 | 内容 |
|---|---|
| `patches/` | 所有补丁。一个补丁一个文件夹(有 `apply.sh` 的);大类文件夹只用来归类和一次选一批 |
| `toolkit/` | 构建框架:`build.sh`(构建)、`build-9008.sh`(构建 + 9008 包)、`select.sh`(看/挑补丁)、`gen-index.sh`、`run-module.sh`(单跑一个补丁)、`lib/`(补丁用的公共函数、`select.sh` 选择逻辑)、`tests/`、`avb/`、`apex/`、`vendor-bind/`、`flash9008/` |
| `devices/<设备>/` | `device.conf`(补丁目录、路径、签名)、`conf.d/*.conf`(各补丁的参数)、`profiles/`(选择预设) |
| `docs/` | `MODULE-SPEC.md`(补丁怎么写)、`FLASH-9008.md`、`AVB-RESIGN.md`;`topics/` 是几个旧组的背景说明(Wi-Fi APEX、免 root 核心、boot 落地…) |
| `private/` | 不进仓库:私有二进制、keybox、签名 key(见各补丁 README 的"输入") |
| `out/` | 构建输出(不进仓库) |

## 能单独发布的

`hotspot-control`/`hotspot-6ghz-unlock`、`navbar-hide`、`herald-core` + `spoof/`、`boot-assemble` 加 `toolkit/` 写成了不绑定 TB321FU(设备相关的值都在 `device.conf`),以后可以拆出去发 GitHub。herald 的引擎二进制和 keybox 是私有的,公开时只发脚本、sepolicy 和文档。

## 和工程目录的关系

仓库的上一级就是 GSI 工程(`device.conf` 的 `OLD` 自动取它),大文件和私有件都在那里,不复制进仓库:

| 工程里的位置 | 内容 |
|---|---|
| `inputs/` | 构建输入:`base/`(Mystic 原版 zip)、`base-fw-a15/`(原厂 boot/vbmeta 等)、`tools/`(xdelta3、pif-toolchain 等) |
| `releases/` | 各版本成品:镜像和报告、9008 补丁包 |
| `legacy/` | V1–V66 手工流程的构建脚本和源码(`gsi/`、`overlay/`、`faceunlock/`…)。`gsi/strong/herald-payload` 是 herald 的私有 payload,`faceunlock/incoming/tools` 是 dex2jar/r8/apktool,构建仍在用 |
| `doc/` | 后端接口文档(`herald-backend-api.md`)、研究笔记,`doc/history/` 是旧的 README、FIXES、TEST 和发布说明 |
