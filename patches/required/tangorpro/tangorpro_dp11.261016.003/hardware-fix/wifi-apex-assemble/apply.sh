# wifi-apex-assemble:把前面各个贡献者登记到 wifi-service-jar 的 smali 补丁一次性应用,
# 回编 service-wifi.jar → 校验 → 写回 APEX payload → 重签 payload 和外层 → 换掉树里的 APEX。
# 必须排在所有 wifi 贡献者后面。登记格式和原理见 README.md。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

APEXTOOL=(python3 -I "$TOOLKIT/apex/apextool.py" --avbtool "${AVBTOOL:-$TOOLKIT/avb/avbtool.py}" --tmpdir "$WORK")
JARTOOL=(python3 -I "$TOOLKIT/apex/jartool.py")
JAR_PATH=javalib/service-wifi.jar
ART=wifi-service-jar

# ---- 没有任何贡献者:干净地跳过,APEX 保持原样(这样可以随意关掉 wifi 的贡献者模块,不用同时删本模块)----
# 贡献者要排在本模块前面;排在后面的会在收尾时被 check_contribs 报出来。
mapfile -t PATCHES < <(contrib_list "$ART")
if (( ${#PATCHES[@]} == 0 )); then
    log "没有任何模块给 $ART 登记补丁,Wi-Fi APEX 保持原样"
    contrib_consume "$ART"
    return 0
fi

# ---- 前提 ----
: "${WIFI_APEX_FILE:?device.conf / conf.d/wifi.conf 没设 WIFI_APEX_FILE}"
for v in APKTOOL_JAR WIFI_APEX_AVB_KEY WIFI_APEX_CERT_X509 WIFI_APEX_CERT_PK8; do need_input "$v"; done
for t in java apksigner zipalign debugfs e2fsck resize2fs patch; do need_tool "$t"; done
need_file "$WIFI_APEX_FILE"
declare -A MARKER
for p in "${PATCHES[@]}"; do
    MARKER[$p]=$(contrib_marker "$p")
    [[ -n ${MARKER[$p]} ]] || die "登记的补丁 $(basename "$p") 没有校验标记(contrib_add 的第三个参数)"
done
log "收到 ${#PATCHES[@]} 个补丁:$(printf '%s ' "${PATCHES[@]##*/}")"

APK() { java -jar "$APKTOOL_JAR" "$@"; }

# ---- 1. 现取 jar ----
sudo cat "$SYS/$WIFI_APEX_FILE" > "$WORK/orig.apex"
"${APEXTOOL[@]}" extract "$WORK/orig.apex" "$JAR_PATH" "$WORK/service-wifi.orig.jar"

# ---- 2. 反编译 + 按登记顺序打补丁 ----
# 补丁在临时的 smali 目录里一个个打(这时树里的 APEX 还没动),后面的补丁可以建立在前面的基础上。
# 任何一个失败都停下,宁可构建失败也不出半成品。
APK d -f -p "$WORK/apktool-fw" -o "$WORK/smali" "$WORK/service-wifi.orig.jar" \
    || die "apktool 反编译 service-wifi.jar 失败"
TARGETS=()
for p in "${PATCHES[@]}"; do
    name=$(basename "$p")
    tgt=$(sed -n 's|^+++ b/||p' "$p")
    [[ $(wc -l <<<"$tgt") == 1 && -n $tgt ]] || die "$name 里应当正好改一个文件"
    [[ -f $WORK/smali/$tgt ]] || die "$name 要改的 $tgt 在当前底包的 jar 里不存在(类被改名或移走了)"
    grep -qF -- "${MARKER[$p]}" "$WORK/smali/$tgt" \
        && die "$tgt 里打 $name 之前就已经有它的标记,底包可能已经打过补丁,或者两个模块登记了重复的改动"
    # --fuzz=0:上下文必须一字不差,换了底包、方法变了就打不上,而不是偷偷打到别处
    patch -d "$WORK/smali" -p1 --fuzz=0 --forward --no-backup-if-mismatch -s < "$p" \
        || die "$name 打不上 $tgt:底包的这个类和补丁预期的不一样,或者缺了它依赖的前置模块(见 docs/topics/wifi.md),要对照新底包重做补丁"
    grep -qF -- "${MARKER[$p]}" "$WORK/smali/$tgt" || die "$name 打完后 $tgt 里没有它自己的标记 ${MARKER[$p]},补丁和标记对不上"
    log "补丁 $name 已打上"
    [[ " ${TARGETS[*]} " == *" $tgt "* ]] || TARGETS+=("$tgt")
done

# ---- 3. 回编,只换 dex ----
APK b -p "$WORK/apktool-fw" -o "$WORK/built.jar" "$WORK/smali" || die "apktool 回编失败(smali 有错)"
[[ -s $WORK/built.jar ]] || die "apktool 回编出的 jar 是空的"
"${JARTOOL[@]}" swap-dex "$WORK/service-wifi.orig.jar" "$WORK/built.jar" "$WORK/service-wifi.jar"
[[ -s $WORK/service-wifi.jar ]] || die "产物 jar 是空的"

# ---- 4. 校验回编结果:再反编译一次,补丁标记都在,且和打完补丁的 smali 指令一致 ----
APK d -f -p "$WORK/apktool-fw" -o "$WORK/check" "$WORK/service-wifi.jar" || die "产物 jar 反编译失败"
for p in "${PATCHES[@]}"; do
    tgt=$(sed -n 's|^+++ b/||p' "$p")
    grep -qF -- "${MARKER[$p]}" "$WORK/check/$tgt" || die "回编后的 $tgt 里找不到 $(basename "$p") 的标记: ${MARKER[$p]}"
done
"${JARTOOL[@]}" smali-equiv "$WORK/smali" "$WORK/check" "${TARGETS[@]}"
log "产物 jar 校验通过($(stat -c %s "$WORK/service-wifi.jar") 字节,${#PATCHES[@]} 个补丁标记都在)"
log "产物 classes.dex sha256: $(unzip -p "$WORK/service-wifi.jar" classes.dex | sha256sum | cut -c1-16)…"

# ---- 5. 写回 APEX,重签(apextool 自带校验:payload 文件树、AVB、apex_pubkey、APK 签名)----
"${APEXTOOL[@]}" repack "$WORK/orig.apex" "$WORK/new.apex" \
    --replace "$JAR_PATH=$WORK/service-wifi.jar" \
    --avb-key "$WIFI_APEX_AVB_KEY" --avb-algorithm "${WIFI_APEX_AVB_ALGORITHM:-SHA256_RSA4096}" \
    --cert "$WIFI_APEX_CERT_X509" --pk8 "$WIFI_APEX_CERT_PK8"
"${APEXTOOL[@]}" extract "$WORK/new.apex" "$JAR_PATH" "$WORK/readback.jar" >/dev/null
cmp -s "$WORK/readback.jar" "$WORK/service-wifi.jar" || die "从新 APEX 的 payload 读回的 jar 和产物不一致"
log "从新 APEX 读回的 service-wifi.jar 与产物逐字节一致"

# ---- 6. 换进树里(保留属主/权限/SELinux 标签)----
if [[ $WIFI_APEX_FILE == *.capex ]]; then
    # 输出是完整 APEX,不是 CAPEX:按 .apex 放,沿用原文件的属性,再删掉 .capex
    dst=${WIFI_APEX_FILE%.capex}.apex
    attr=$(sudo stat -c '%a %u:%g' "$SYS/$WIFI_APEX_FILE")
    put "$WORK/new.apex" "$dst" "${attr% *}" "${attr#* }" "$(get_label "$SYS/$WIFI_APEX_FILE")"
    remove "$WIFI_APEX_FILE"
else
    replace "$WORK/new.apex" "$WIFI_APEX_FILE"
fi
contrib_consume "$ART"
rm -rf "$WORK/smali" "$WORK/check" "$WORK/apktool-fw" "$WORK/built.jar" "$WORK/readback.jar"
log "完成:$(sha256sum "$WORK/new.apex" | cut -c1-16)  $WIFI_APEX_FILE"
