# wifi-apex-assemble — Wi-Fi APEX 打包

## 做什么

assemble 模块。把前面各个 Wi-Fi 贡献者模块登记的 smali 补丁**一次性**应用到 Wi-Fi Mainline APEX 里的 `service-wifi.jar`,
回编、校验、重签 APEX、换进树里。贡献者本身不碰 APEX,所有"回编和重签"都在这里做,所以 APEX 只重打一次。
不内置任何底包二进制:jar 每次从当前底包的 APEX 里现取。

## 登记格式(给贡献者模块的接口)

产物名固定为 **`wifi-service-jar`**。贡献者在 `apply.sh` 里写:

```bash
contrib_add wifi-service-jar "$MOD/patches/01-xxx.diff" '<校验标记>'
```

- **文件**:一个 unified diff,`patch -p1` 格式,路径前缀 `a/smali/…`、`b/smali/…`,即相对 apktool 反编译出来的目录。
  一个 diff 只改一个 smali 文件(assemble 从 `+++ b/` 行读目标文件,不是一个就报错)。想改多个文件就登记多个 diff。
- **校验标记**:一个固定字符串(必填)。assemble 保证:打补丁**之前**它不在目标文件里(在就说明底包已打过补丁或有人重复登记),
  打完**之后**在,回编再反编译之后**仍然**在。选补丁里独有的一行,例如 `const-string v1, "herald_wifi_country"`。
- **顺序**:按登记顺序(`MODS` 里的顺序)一个个打,后一个补丁的上下文可以建立在前一个已打上的基础上。
  assemble 在临时目录里打,任何一个失败都停下,树里的 APEX 不动。

没有任何贡献者登记时 assemble 干净地跳过,APEX 保持原样(这样可以随意关掉 wifi 的贡献者模块,不用同时删本模块);有贡献者但 `MODS` 里没有 assemble,构建收尾时会失败(`check_contribs`),不会悄悄少改动。

## 流程

1. 检查输入和工具,取出登记的补丁;
2. `sudo cat` 底包的 APEX,用 `toolkit/apex/apextool.py extract` 取出 `javalib/service-wifi.jar`;
3. apktool 反编译,按登记顺序 `patch --fuzz=0 --forward` 逐个打(上下文必须一字不差);
4. apktool 回编,`toolkit/apex/jartool.py swap-dex` 只把新 `classes.dex` 换进原 jar(其它条目原样);
5. 校验:产物 jar 再反编译一次,每个补丁的标记都在,且和打完补丁的 smali 指令一致(`jartool.py smali-equiv`,标签名除外);
6. `apextool.py repack` 写回 payload 并重签,自带校验;再从新 APEX 读回 jar,逐字节比较;
7. 用 `replace`(保留属主、权限、SELinux 标签)换进树里;底包是 `.capex` 时按 `.apex` 放,删掉 `.capex`;
8. `contrib_consume wifi-service-jar`。

## 为什么能重签 APEX,什么不能碰

APEX 是个 zip:`apex_payload.img` 是 ext4 镜像,带 AVB hashtree footer;`apex_pubkey` 是验它的 AVB 公钥;整个 zip 再按 APK 签名。
原版是 Compressed APEX(CAPEX),外壳里的 `original_apex` 才是完整 APEX。

重签做法(`toolkit/apex/apextool.py repack`):

1. 解开 CAPEX 拿 `original_apex`,取出 `apex_payload.img`,`avbtool erase_footer` 去掉 hashtree,剩纯 ext4。
2. payload 的 ext4 带 `shared_blocks` 特性,内核不让读写挂载,用 `debugfs -w` 直接改镜像:删旧文件、写新文件、
   把属主(1000:1000)、权限(0644)、时间戳、SELinux 标签(`u:object_r:system_file:s0`)按原文件设回去。空闲块不够时先 `resize2fs` 扩一点。
3. `e2fsck` 检查干净,逐个核对 payload 里所有文件:只有被换的文件内容变了,其它文件内容、属主、权限、xattr 都没变。
4. 用自己的 key(这里是 AOSP `testkey_rsa4096`)重做 hashtree footer,salt、分区名、hash 算法、`apex.key` prop 都沿用原版。
5. `apex_pubkey` 换成这把 key 的公钥(`avbtool extract_public_key`)。
6. 不复原 CAPEX 外壳(没搞清它的签名机制),直接放完整 APEX(文件从 3.6MB 变成 9MB 左右);zip 条目和顺序照原版,
   去掉旧签名和 `stamp-cert-sha256`,`zipalign 4096`,`apksigner` 用 testkey 重签(v1/v2/v3)。

能行的原因:出厂预装(`/system/apex`)、不走 OTA 更新的 APEX,apexd 只做自洽校验——payload 的 AVB 签名能被同一个 zip 里的
`apex_pubkey` 验过就激活,不比对系统里写死的 Google 证书。V49 真机证实(Wi-Fi 正常,`dumpsys wifi` 三处国家码都是补丁设的值)。

**不能碰 APEX 里 `app/`、`priv-app/` 下的 APK**(`ServiceWifiResourcesGoogle.apk`、`WifiDialogGoogle.apk`、`OsuLoginGoogle.apk`)。
它们是 PackageManager 按普通 APK 扫描安装的,设备上 `/data/system/packages.xml` 记着 Google 的原签名,换签名会被签名延续性检查拒掉,
包就"不存在"了。V50 改了 `ServiceWifiResourcesGoogle.apk`,`WifiContext` 拿不到 `com.android.wifi.resources`,
`WifiInjector.<init>` 空指针,system_server 反复崩溃,开机卡在第二屏。`javalib/` 下的 jar 不是安装包,不走这条检查,可以改。
所以以后给 Wi-Fi 加改动,只能往 `service-wifi.jar` 的 smali 里加,不要改资源 APK。

## 改动清单

- 修改 `system/apex/com.google.android.wifi.apex`:从 CAPEX 变成完整 APEX(约 9MB),payload 里只有 `javalib/service-wifi.jar` 不同,
  `apex_pubkey` 和 APK 签名换成自己的 key。属主、权限、SELinux 标签保持原文件的。
- `service-wifi.jar` 里只换了 `classes.dex`,其它条目(`.uau`、`META-INF/MANIFEST.MF`)原样。dex 里改了哪些类由各贡献者模块的 README 列。
- apktool 回编会让 `WifiAwareDataPathStateManager.sVdbg`、`LogcatLog.sVerboseLogging`、`WifiChannelUtilization.sVerboseLoggingEnabled`
  三个静态字段丢掉 `= false` 初值,默认值本来就是 false,没有影响。

## 输入

`devices/<设备>/conf.d/wifi.conf`(或 `device.conf`)提供:

| 变量 | 说明 |
|---|---|
| `WIFI_APEX_FILE` | system 下的 APEX 路径,默认写 `apex/com.google.android.wifi.apex`。底包里是 `.capex` 就写 `.capex`,模块会放成同名 `.apex` 并删掉 `.capex`。四个 wifi 模块都读这个变量 |
| `WIFI_APEX_AVB_KEY` | payload 的 AVB 私钥(PEM)。AOSP 的 `external/avb/test/data/testkey_rsa4096.pem` 就行,任意 RSA 私钥也行。设备如果校验 APEX 公钥,要用设备信任的 key |
| `WIFI_APEX_AVB_ALGORITHM` | 可选,默认 `SHA256_RSA4096`,要和 key 的位数匹配 |
| `WIFI_APEX_CERT_X509`、`WIFI_APEX_CERT_PK8` | 外层 APK 签名的证书和私钥。用 AOSP `build/make/target/product/security/testkey.x509.pem` / `testkey.pk8` |
| `APKTOOL_JAR` | apktool 2.12.1 或更新(旧版处理不了 A15 的 dex)。补丁按 2.12.1 的反编译结果做的 |
| `AVBTOOL` | 可选,默认 `toolkit/avb/avbtool.py` |

key 都不放进仓库,自己从 AOSP 源码取或自己生成。需要的工具:java 17、apksigner、zipalign、e2fsprogs(debugfs、e2fsck、resize2fs)、patch。

## 依赖和顺序

排在 `wifi-country-code`、`hotspot-6ghz-unlock`、`hotspot-overrides` 全部后面。不用 `require_mod`,启用哪几个贡献者就处理哪几个。

## 适用范围和换底包注意

补丁按 Android 15 的 Wi-Fi 模块做(官方 Pixel 原厂 GSI BP1A.250505.005 带的 `com.google.android.wifi`,
模块版本 350820380,原 CAPEX sha256 前缀 `e1d2fc24`)。换底包时会在这些地方停下:

- 底包里没有这个 APEX → 贡献者的 `need_file` 和这里都会报错。
- APEX 里没有 `javalib/service-wifi.jar` → apextool extract 报错。
- 补丁打不上 → 报"`NNN-模块-xxx.diff` 打不上 …"。
- 标记已经在打补丁之前出现(底包已经是改过的系统,或有两个模块登记了同样的改动)→ 报"已经有标记"。
- 回编后的 smali 和补丁不一致、标记不在、产物 jar 为空、payload 读回的 jar 和产物不一致、payload 其它文件有变化、AVB 或 APK 签名验不过 → 都会停。

### 换底包补丁打不上怎么办

补丁用 `patch --fuzz=0`,WiFi 模块版本一变多半会在这里停。不要放宽 fuzz,要对照新底包重做:

1. `java -jar apktool.jar d service-wifi.jar -o orig`(jar 用 `toolkit/apex/apextool.py extract` 从 APEX 里取),复制一份成 `new`;
2. 在 `new` 里按对应贡献者 README 的"原理"一节手工把改动搬过去(方法改名、寄存器变了就按新代码调整),新加的标签用 `:herald_` 前缀,别和原有标签撞;
3. `diff -u -U5 --label a/smali/<路径> --label b/smali/<路径> orig/smali/<路径> new/smali/<路径> > patches/NN-xxx.diff`;
4. 确认 `apply.sh` 里登记的标记字符串还在新补丁里。

几个补丁改同一个文件时(例如 `SoftApManager.smali`),每个补丁要单独对**原版**做 diff,再确认能按登记顺序依次打上,也能各自单独打上。

## 踩过的坑

- **V49**:第一次改 APEX。`WifiCountryCode` 不在 services.jar,在 Wi-Fi Mainline APEX 里;payload 的 ext4 有 `shared_blocks`,
  内核挂不上读写,改用 debugfs。apexd 接受自签 APEX 当时是假设,真机证实成立。
- **V50**:改了 APEX 里 `ServiceWifiResourcesGoogle.apk`,重签后被 PackageManager 拒装,system_server 崩溃,开机卡死。回退 V49。见上文"不能碰"。
- **V57 首发卡开机**:smali 里替换代码块时字符串匹配命中了跳转引用而不是标签行,标签重复,apktool 回编失败;
  构建脚本把输出管给 tail/grep 吞了错误,debugfs `rm` 成功、`write` 一个不存在的文件静默失败,APEX 里的 jar 是空的,
  system_server 报 `ClassNotFoundException WifiService`。教训(本模块都做了):`set -euo pipefail`、不用管道吞 apktool/debugfs 的输出、
  debugfs 的 stderr 一律当错误、出包前核对产物 jar 非空并从 payload 读回逐字节比较、回编后再反编译查补丁标记。
- **模块化时(V67)**:V64 的 payload 是在 V49 的 payload 上改的,`erase_footer --keep_hashtree` 把旧 hashtree 留在了 ext4 后面,
  分区名也从空变成了 `apex_payload`、salt 变成随机。功能没问题,本模块改成从原版现取,footer 参数照原版。
  拆成四个模块后,三个贡献者全开的产物 `classes.dex` 和拆分前(V66)逐字节相同(sha256 `f5c8e526…`)。

## 验证

构建日志里 `产物 classes.dex sha256: …` 一行和各项"通过"。也可以单独核对:

```bash
python3 toolkit/apex/apextool.py verify 新.apex --orig 原.apex --avb-key testkey_rsa4096.pem \
    --changed javalib/service-wifi.jar
```

刷机后:Wi-Fi 能正常开;如果完全起不来,`adb logcat | grep -iE 'apexd|WifiService'`,看 apexd 是否拒绝了这个 APEX、jar 是否为空。
各项功能的验证见贡献者模块的 README。
