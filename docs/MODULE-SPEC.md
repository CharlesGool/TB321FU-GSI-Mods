# 补丁约定

**一处改动 = 一个补丁 = 一个文件夹。** 能分开说清楚的改动就拆开:三个 overlay 是三个补丁,一个 overlay 里有两个互不相干的修复(亮度、屏幕方向)也是两个补丁。拆开的好处:
各自写原理、各自能关、坏了好定位、能单独拿出去用、维护时只看自己的文件夹。

## 目录

```
patches/<补丁>/              一个补丁(有 apply.sh 的文件夹就是补丁)
  patch.conf    必须。身份:名字、一句话说明、阶段、依赖、顺序、运行时开关(见下面"patch.conf")
  README.md     必须。原理文档,见下面"README 要写什么"
  apply.sh      必须,可执行。在工作树上做改动
  files/        原样放进镜像的文件
  src/          需要编译的源码和构建脚本
  patches/      对底包文件打的补丁(smali diff 等)
patches/<大类>/<补丁>/       同一大类的补丁放一个文件夹(slim/old-vndk、perf/cpu-freq)
patches/<大类>/README.md     大类说明:解决什么问题、里面的补丁表、补丁之间的关系
```

**补丁名 = `patches/` 下的相对路径**(`herald-core`、`battery`、`perf/cpu-freq`、`slim/old-vndk`),`device.conf`、`REQUIRES`、选择规则里都写这个。

**什么时候放进大类文件夹**:做的是同一件事、但各自能单独起作用的(精简的几类、伪装的三种方式、亮度的修复和非常规修改)。只是名字沾边的不放一起:热点入口(设置里的 UI)和热点行为(改 Wi-Fi APEX)是两件事,分开;亮度和刷新率分开。大类文件夹本身不是补丁,只用来归类和一次选一批(`WITHOUT=battery`)。大类里可以再分小类(`slim/apps/`)。

改 boot 的补丁也在 `patches/` 下,和别的补丁一样排在 `MODS` 里。构建时 GSI 和原厂固件在同一个工作区:`TREE` 是 system 树,`FW_OUT` 是固件目录,一个补丁可以两边都改(`selinux/fix`)。`patch.conf` 的 `STAGE` 只说明改的是哪边:`system` / `firmware` / `both`。

## 合并补丁(parts/)

几个部分**修的是同一件事、合起来才完整**(蓝牙的三处修复、自动亮度修复的四个 overlay、热点控制的三处 APEX 补丁),或者**关联太紧、拆开单独打没有意义**(共用一个公共底座、"钩子 + 开关"一对、缺一个整个功能就不工作)的,合成一个补丁,只能整个打或整个不打。**非常规的修改不合进去**,单独成补丁(例如 `brightness/hbm-unlimited` 不在 `brightness/stock` 里)。

```
patches/required/general/hardware-fix/bluetooth-fix/
  patch.conf      和普通补丁一样;REQUIRES 只写外部依赖
  README.md       整体说明 + 部分表
  apply.sh        外部依赖的 require_mod + run_parts
  parts/001.profile-props/        part.sh + README.md + files/ src/ …
  parts/002.a2dp-offload-policy/
  parts/003.sco-call-fix/
```

- 部分的文件夹叫 `NNN.<部分名>`,编号从 001 连续,**就是执行顺序**。`run_parts`(`toolkit/lib/common.sh`)按编号跑,每部分在自己的子 shell 里,`MOD`/`WORK` 指向这一部分,`MOD_NAME=<补丁名>/<部分名>`。
- `part.sh` 写法和 `apply.sh` 一样,但不写 `require_mod`:部分之间靠编号,外部依赖写在补丁的 `apply.sh` 和 `patch.conf`。部分里不放 `apply.sh` / `patch.conf`(它不是补丁)。
- 部分不能单独选(`WITHOUT=battery/charge-limit` 会报"没有匹配的补丁")。哪天某个部分需要单独开关了,就把它挪出来成为独立补丁。
- 加一个部分:建 `parts/<下一个编号>.<名字>/`,放 `part.sh` 和 `README.md`;要插到中间就把后面的顺延改号。

## patch.conf

每个补丁的身份文件,bash 语法(会被 `source`)。**真正的 `patch.conf` 不写注释**,带注释的模板在 `docs/patch-template/`,新建补丁用 `toolkit/new-patch.sh <名字> [--parts]`。选补丁、自动补依赖、核对顺序、`make list`、补丁总表全都读它,所以**依赖和顺序要求只写在这里**,不要只写在注释里。

```bash
NAME=perf-game-boost                        # = 文件夹路径
VERSION=V1.0                                # 补丁版本号 V<数字>.<数字>(可带后缀,如 V1.0-test);新补丁从 V1.0 起,每次改补丁都要 +
TITLE='游戏性能联动'                        # 中文名,几个字,表格和 make list 里显示
DESC='游戏模式的性能档钩子'                      # 一句话,make list 和补丁总表里显示
STAGE=system                                # 改哪边:system | firmware | both(只是说明,执行顺序看 MODS)
REQUIRES=(game-mode herald-core perf)          # 必须一起打,并且排在本补丁前面(没选会自动带上)
AFTER=()                                    # 只管顺序:这些如果也打了,要排在本补丁前面(不选也行)
BEFORE=()                                   # 只管顺序:这些如果也打了,要排在本补丁后面
WANTS=()                                    # 软依赖:选了本补丁就顺带打上它们;被明确去掉也不连累本补丁(改 jar 的补丁写 WANTS=(stale-boot-image))
CONTRIBUTES=()                              # 往哪些产物登记改动(见下面"贡献"),会自动带上负责它的 assemble 补丁
ASSEMBLES=()                                # 负责把哪些产物收到的登记一次性打上(assemble 补丁才有)
RUNTIME='heraldctl game perfprofile'           # 装好后在设备上怎么开关;空 = 只能构建时选
RISKS=''                                    # 可能的问题:已知的副作用、可能被检测到的地方、没验证过的部分;大部分补丁没有这一项,不写就是没有已知问题
DEFAULT=on                                  # 只对 optional/* 有意义,说明性的:这个补丁通常是不是默认装(on/off);不写就是 on。
                                             #   不驱动向导逻辑——真正决定 make-9008.sh 向导默认答案、和不跑向导时打哪些的,是各设备自己
                                             #   device.conf 的 MODS_OFF(设备之间本来就可以不一样,如 bp1a/tangobeta 的默认比主设备宽松)。
                                             #   这个字段只是让补丁自己说清楚"正常情况下默认怎样",和主设备 tb321fu-a15 的 MODS_OFF 要对得上
                                             #   (toolkit/tests/test-patch-meta.sh 查这条,只查主设备)。向导不管这个字段是什么,问还是会问。
```

和 apply.sh 的关系:`REQUIRES` 要和 apply.sh 里的 `require_mod` 一致,`CONTRIBUTES` 要和 `contrib_add` 的产物名一致,调了 `contrib_consume` 的要写 `ASSEMBLES`。`toolkit/tests/test-patch-meta.sh` 检查这些,也检查每个设备的 `MODS` 顺序满足 `REQUIRES`/`AFTER`/`BEFORE`。

补丁版本号 `VERSION`:格式 `V<数字>.<数字>`,可带后缀(如 `V1.0-test`)。**每次改一个补丁(它目录下任何文件:diff、脚本、files、README)都要更新它自己的 `VERSION`,无论改动是否让补丁正常工作。** 这样每次改动在 git 里都带一个显式版本号,便于区分和管理;构建输出的 `MODULES.txt`(`补丁名<TAB>版本`)和 `SELECTION.txt`(`patch: 名字@版本`)都记录了这次用的是哪版。`test-patch-meta.sh` 对着 git `HEAD` 查:某补丁目录相对 HEAD 有改动(含未跟踪新文件)、但 `VERSION` 和 HEAD 里的一样,就报错——所以改补丁和升版本号要在同一次提交里。新补丁从 `V1.0` 起(HEAD 里还没有它、或 HEAD 的 `patch.conf` 还没 `VERSION` 的,都不算"没升")。

改了 `patch.conf`(或加/删补丁)后跑 `toolkit/gen-index.sh` 重新生成补丁总表 `patches/README.md`。

## 加一个补丁

1. 建 `patches/<名字>/`(或放进合适的大类文件夹),写 `apply.sh`、`README.md`、`patch.conf`。
2. 把名字加进 `devices/<设备>/device.conf` 的 `MODS` 里合适的位置——这里定执行顺序。默认不想打就同时加进 `MODS_OFF`。
3. `toolkit/run-module.sh` 单跑调试;`toolkit/tests/test-patch-meta.sh`、`toolkit/gen-index.sh`;`make test` 跑独立性测试。

## apply.sh 的运行环境

`apply.sh` 被 `source` 进一个已经加载了 `toolkit/lib/common.sh` 的 bash(`set -euo pipefail`)。

| 变量 | 含义 |
|---|---|
| `TREE` / `SYS` | 工作树根(等于 GSI 镜像的根)/ `$TREE/system` |
| `FW_OUT` | 固件目录:里面已有原厂 init_boot / vendor_boot,改 boot 的补丁把 boot.img 写这里 |
| `MOD` / `MOD_NAME` | 本补丁目录 / 本补丁名(`patches/` 下的相对路径,如 `perf/cpu-freq`;合并补丁的部分里是 `<前缀>/<部分>`,如 `battery/charge-limit`) |
| `WORK` | 本补丁的临时目录,每次构建都是空的 |
| `BUILD_STATE` | 本次构建的状态目录(补丁之间传话用,见下面"依赖"和"贡献") |
| `TOOLKIT` / `REPO` / `DEVICE_DIR` | 工具链目录、仓库根、设备配置目录 |
| `VERSION` 等 | `device.conf` 和 `conf.d/*.conf` 里定义的所有变量(补丁参数都写在那里) |

工作树里的文件是 root 属主、带 SELinux xattr 的。改动一律用 `common.sh` 里的函数:
`put_dir`、`put`、`replace`、`remove`、`edit`、`append`、`prop`、`cil_append`、`fc_append`。
**不要直接 `sudo sed -i`**:会换 inode,丢标签、权限变 0600(V60/V64 踩过)。
检查类的语句写 `if 条件; then die "…"; fi`,不要写 `条件 && die "…"`:后者条件不成立时整条语句的退出码是 1,放在补丁最后一行会让补丁被当成失败(框架做了兜底,但别依赖)。

## 换底包时的行为

用户会换 GSI 底包,也会换 vendor/boot 底包(原厂固件)。补丁必须:

1. **先检查前提再动手。** 要改的文件、要打补丁的方法、要替换的 key 不存在,或者补丁打不上,就 `die` 并说明原因。
   宁可构建失败,也不要出一个看起来成功、其实少了改动的镜像。
2. **从底包现取,不内置底包的二进制。** 例如 services.jar 补丁要从当前底包的 services.jar 反编译、打补丁、回编;
   vendor 相关的补丁从 `device.conf` 指定的原厂 vendor 里取原文件现打。预编译件(overlay apk、App)可以放在 `files/`,但 `src/` 要有源码和构建脚本。
3. **依赖原厂固件的补丁**要在 README 里写清楚依赖哪个分区的哪个文件,以及换固件后要核对什么。
4. **删东西的补丁:底包里本来就没有就跳过**(`remove`/`remove_list` 已经这样做,记一行"底包里没有 K 项"),不算失败;只有"一项都没删到说明目录结构变了"时才用 `--require-any` 报错。
5. 目标是换 GSI 来源 / 安卓版本时**大部分补丁照样能用**,不能用的明确报错。换底包先跑 `make survey BASE_GSI=…`(`toolkit/survey.sh`)看哪些要重做。

## 独立性(硬性要求)

**补丁之间尽量互不依赖、互不干扰。** 每个补丁都能单独选择打不打:任意子集(依赖自动补上之后)都必须能构建、能用。具体规则:

1. **依赖要少,而且要写明。** 真依赖只有这几种:挂在免 root 核心上的(`REQUIRES=(herald-core)`),同一功能的底座(`game-mode`、`perf`)。写进 `patch.conf` 的 `REQUIRES`,apply.sh 里同时 `require_mod`。
2. **不依赖别的补丁先改过什么,也不改别的补丁的文件。** 两个补丁要改同一个文件时,各改各的键/各的段,谁先谁后结果都对(`prop`/`append`/`cil_append` 都是这样的)。
3. **功能上有关联的,构建不能失败。** 比如只装人脸 App 不装 services 补丁,人脸用不了,但构建要过,README 里写清楚。
4. **多个补丁共用的机制是库,不是补丁。** 放在 `toolkit/lib/`,第一次用到时自动装、之后幂等(例如 `vendor_bind_add` 第一次调用时装上开机 bind 脚本,蓝牙的两个补丁各自调用,谁单独启用都行)。
5. **共用一个产物的改动用"贡献 + assemble"**(见下)。assemble 一个贡献都没有时要么干净地跳过、要么报清楚的错,不能把产物弄坏。
6. **善后类补丁靠标记判断,不靠"排在后面"碰运气。** 例如 `stale-boot-image` 用 `was_modified` 看前面有没有人改过 jar,什么都没改就什么都不删。
7. 每个补丁的 README 有一栏"运行时开关"(见下)。

## 运行时开关

构建时选"打不打"是第一层。有些改动适合再加第二层:装好以后在设备上用命令开关(不用重刷)。需不需要,按这处改动的性质看:

- **适合**:改动本来就是"开关式"的 —— 导航栏隐藏(`heraldctl navbar hide|show`)、全局伪装(`heraldctl spoof set|off`)、热点参数覆盖(Settings 键,`heraldctl wifi set`)。
- **不适合**:删应用、改 sepolicy、改 build.prop、改 jar —— 开关没有意义或者做不到。
- **可以做成开关但目前没做**:纯资源覆盖的 overlay(亮度曲线、屏幕方向、热点入口)。做法是把静态 RRO 改成非静态,再加一个 broker 插件用 `cmd overlay enable/disable` 控制,和 `navbar-hide/control` 同一套路。要不要做,以后看需要。

开关一律走 免 root 核心的插件机制(接口见 `patches/required/general/herald-core/README.md`)(`herald-core` 的 `plugins/` 和 heraldctl 的 `heraldctl.d/`),不单独造通道。有开关的补丁,README 里写清楚命令和默认状态。

## 补丁之间的关系

### 依赖:`require_mod 补丁名`

和 `patch.conf` 的 `REQUIRES` 一一对应。构建时选择器已经保证依赖被选上、排在前面;apply.sh 里的 `require_mod` 是第二道保险(用 `toolkit/run-module.sh` 单跑时也能报错)。

### 看别的补丁开没开:`mod_ran 补丁名`

只返回真假,不报错。用在"另一个补丁打了就换一种做法"的地方(例如 `zuicamera/hide-unsupported` 看 `macro-camera-fix` 打没打,决定留不留微距),以及改 jar 的补丁检查 `stale-boot-image` 还没跑。**不要直接查 `$BUILD_STATE/ran/` 下的文件**:那是补丁名换写法后的文件名,改名时会悄悄失效(整理前就有两处因为组名改过一直没生效)。只管顺序的关系同时写进 `patch.conf` 的 `AFTER`/`BEFORE`。

### 贡献:多个补丁给同一个产物提改动

有些产物只能整体重打一次(Wi-Fi APEX 要重签 payload,boot 要重签 AVB),但里面几处改动又该各自成补丁。做法:

- **贡献者补丁**:只把自己那份登记进去,不动产物。`contrib_add <产物名> <文件> [校验标记]`(或 `contrib_add_text`)。
- **assemble 补丁**:排在所有贡献者后面。用 `contrib_list <产物名>` 拿到登记的全部东西,一次性应用、打包、签名,最后调用 `contrib_consume <产物名>`。
- `MODS` 里只启用其中几个贡献者,assemble 就只处理这几个。
- 收尾时如果有产物收到了贡献但没有被 consume(忘了加 assemble),构建会失败。
- 贡献者的补丁必须**各自独立**:每个都能单独打到原始文件上,任意子集、任意顺序都能打上、能回编。几个补丁在功能上必须捆在一起的(例如一个补丁调用另一个补丁新增的方法),就放进同一个补丁,不拆。

登记的内容格式由 assemble 补丁定义,写在 assemble 补丁的 README 里,贡献者补丁的 README 链接过去。

### 改动标记

`mark_modified <路径>` / `was_modified <路径>`:改了会让别的东西失效的文件(jar、…)后登记一下,善后补丁据此决定要不要处理。

## README 要写什么

- **做什么**:一两句话,用户能看懂的效果。
- **原理**:为什么要改、改了哪里、为什么这样改能生效。附关键证据(日志、反编译看到的调用链)。
- **改动清单**:镜像里新增/修改/删除了哪些文件。
- **输入**:需要 `device.conf` 提供哪些变量(原厂文件路径、私有文件路径、参数)。
- **依赖和顺序**:为什么要依赖它们、为什么要排在那里(依赖本身写在 `patch.conf`,这里写原因)。
- **适用范围和换底包注意**:对底包有什么前提,换了底包会在哪一步失败、怎么修。
- **踩过的坑**:历史版本里出过的问题和教训(有版本号)。
- **验证**:刷机后怎么确认生效。

`patch.conf` 里已有的(一句话说明、依赖列表、运行时开关命令)README 不用再抄一遍表格,写原因和细节。

大类 README 里放:这一类解决的问题(一段话)、补丁表(补丁 / 做什么 / 能不能单独关)、补丁之间的关系、单独发布时要带哪些东西。

## 能单独发布的

Wi-Fi 那几个、`navbar-hide/`、`herald-core` + `attestation-fix` + `spoof/` 和 `toolkit/` 以后可能单独发到 GitHub,写的时候:
不写死 TB321FU,设备相关的值做成 `device.conf` 参数;不放私有文件(keybox、私钥、第三方二进制),README 里说明用户自己从哪弄。
