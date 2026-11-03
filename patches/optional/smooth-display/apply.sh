# smooth-display:services.jar 的 DisplayModeDirector 钩子,让设置里"流畅显示"开 = 165Hz(不设上限)、关 = ${SMOOTH_DISPLAY_OFF_HZ:-120}Hz。
# 流程同 faceunlock/services-hooks:现取 services.jar → apktool 反编译 → 打 smali → 回编只换被改的那份 dex → 等价核对 → 换回树里。
need_input APKTOOL_JAR
for t in java zipalign unzip; do need_tool "$t"; done
need_file framework/services.jar
! mod_ran required/general/boot-kernel/stale-boot-image || die "stale-boot-image 已经跑过了,请把它排在本模块后面(MODS 顺序)"
OFF_HZ=${SMOOTH_DISPLAY_OFF_HZ:-120}
[[ $OFF_HZ =~ ^[0-9]+$ ]] || die "SMOOTH_DISPLAY_OFF_HZ 必须是整数,现在是 '$OFF_HZ'"

APK() { java -jar "$APKTOOL_JAR" "$@"; }
sudo cat "$SYS/framework/services.jar" > "$WORK/services.orig.jar"
APK d -f -r -o "$WORK/svc" "$WORK/services.orig.jar" >/dev/null || die "apktool 反编译 services.jar 失败"
sleep 1; touch "$WORK/.patch_stamp"; sleep 1
python3 -I "$MOD/apply_hook.py" "$WORK/svc" "$OFF_HZ" | tee "$WORK/hook.log" | sed 's/^/    /'
grep -q FAIL "$WORK/hook.log" && die "钩子没打上(底包的 DisplayModeDirector 和预期不一样,见 README 换底包一节)"
grep -rqF -- "herald-smooth-display" "$WORK/svc"/smali*/com/android/server/display/mode/ || die "补丁标记没出现在 smali 里"

mapfile -t CHANGED < <(cd "$WORK/svc" && find smali* -name '*.smali' -newer "$WORK/.patch_stamp" | sort)
[[ ${#CHANGED[@]} -eq 1 ]] || die "被改的 smali 是 ${#CHANGED[@]} 个,预期正好 1 个:${CHANGED[*]}"
mapfile -t SWAP < <(printf '%s\n' "${CHANGED[@]}" | sed 's|/.*||; s|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|' | sort -u)
SWAPARGS=(); for d in "${SWAP[@]}"; do SWAPARGS+=(--swap "$d"); done
log "改了 ${CHANGED[0]##*/},换 dex:${SWAP[*]}"
APK b -f "$WORK/svc" -o "$WORK/svc_rebuilt.jar" >/dev/null || die "apktool 回编失败(smali 有错)"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble "$WORK/services.orig.jar" "$WORK/svc_rebuilt.jar" "$WORK/services.jar" "${SWAPARGS[@]}"

APK d -f -r -o "$WORK/check" "$WORK/services.jar" >/dev/null || die "产物 jar 反编译失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/svc" "$WORK/check" "${CHANGED[@]}"
grep -qF -- "# ${OFF_HZ}.0f" "$WORK/check/${CHANGED[0]}" || die "产物里找不到钩子,回编丢了补丁"

replace "$WORK/services.jar" framework/services.jar
mark_modified framework/services.jar     # 告诉 stale-boot-image:services 的预编译产物过期了
log "完成:services.jar $(sha256sum "$WORK/services.jar" | cut -c1-16),流畅显示关 = ${OFF_HZ}Hz"
