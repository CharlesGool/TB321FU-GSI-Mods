# build-consistency-dialog-fix 的 A17 QPR(DEX 041)分支,由 apply.sh source。
# 把 services.jar 里 showSystemReadyErrorDialogsIfNeeded() 对 Build.isBuildConsistent() 的调用换成常量 true:
#   invoke-static {}, Landroid/os/Build;->isBuildConsistent()Z
#   move-result vN                                  →   const/4 vN, 0x1
# 流程同 smooth-display:现取 services.jar → 拆 041 → apktool 反编译 → 改 smali → 回编只换被改的那份 dex → 等价核对 → 换回树里。
need_file framework/services.jar
for t in unzip; do need_tool "$t"; done

sudo cat "$SYS/framework/services.jar" > "$WORK/services.orig.jar"
source "$TOOLKIT/lib/dex041.sh"
undex041_jar "$WORK/services.orig.jar" "$WORK/services.orig.jar"
APK d -f -r -o "$WORK/svc" "$WORK/services.orig.jar" >/dev/null || die "apktool 反编译 services.jar 失败"

SVC_SMALI=$(cd "$WORK/svc" && grep -rl 'showSystemReadyErrorDialogsIfNeeded()V' smali*/com/android/server/wm/ActivityTaskManagerService\$LocalService.smali 2>/dev/null || true)
[[ -n $SVC_SMALI && $(wc -l <<<"$SVC_SMALI") == 1 ]] || die "services.jar 里没找到唯一的 ActivityTaskManagerService\$LocalService.smali(找到:${SVC_SMALI:-0 个})"
python3 -I - "$WORK/svc/$SVC_SMALI" <<'PY' || die "showSystemReadyErrorDialogsIfNeeded 里没找到 isBuildConsistent 调用,底包和预期不一样"
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r'(\.method [^\n]*showSystemReadyErrorDialogsIfNeeded\(\)V\n)(.*?)(\n\.end method)', s, re.S)
if not m:
    sys.exit(1)
body = m.group(2)
pat = re.compile(r'invoke-static \{\}, Landroid/os/Build;->isBuildConsistent\(\)Z\s*\n\s*move-result v(\d+)')
hits = pat.findall(body)
if len(hits) != 1:
    print(f"    isBuildConsistent 调用 {len(hits)} 处,预期 1 处")
    sys.exit(1)
reg = int(hits[0])
op = 'const/4' if reg < 16 else 'const/16'
body = pat.sub(f'# TB321FU: 版本一致性检查短路为 true(不弹"设备内部出现了问题")\n    {op} v{reg}, 0x1', body)
open(p, 'w').write(s[:m.start(2)] + body + s[m.end(2):])
print(f"    已改 showSystemReadyErrorDialogsIfNeeded:isBuildConsistent() -> {op} v{reg}, 0x1")
PY

SWAPDEX=$(echo "${SVC_SMALI%%/*}" | sed 's|^smali_classes|classes|; s|^smali$|classes.dex|; /^classes[0-9]/s|$|.dex|')
log "调用方在 $SWAPDEX,只换这一份 dex"
APK b -f "$WORK/svc" -o "$WORK/svc_rebuilt.jar" >/dev/null || die "apktool 回编 services.jar 失败"
python3 -I "$TOOLKIT/lib/jarpatch.py" assemble \
    "$WORK/services.orig.jar" "$WORK/svc_rebuilt.jar" "$WORK/services.jar" --swap "$SWAPDEX"

# 校验:产物再反编译,弹窗方法里不再调 isBuildConsistent;其余 smali 与改后的等价。
APK d -f -r -o "$WORK/svccheck" "$WORK/services.jar" >/dev/null || die "产物 services.jar 反编译失败"
python3 -I - "$WORK/svccheck/$SVC_SMALI" <<'PY' || die "回编后的 showSystemReadyErrorDialogsIfNeeded 仍在调 isBuildConsistent"
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'\.method [^\n]*showSystemReadyErrorDialogsIfNeeded\(\)V\n(.*?)\n\.end method', s, re.S)
sys.exit(0 if m and 'isBuildConsistent' not in m.group(1) else 1)
PY
python3 -I "$TOOLKIT/lib/jarpatch.py" smali-equiv "$WORK/svc" "$WORK/svccheck" "$SVC_SMALI"
replace "$WORK/services.jar" framework/services.jar
mark_modified framework/services.jar    # 告诉 stale-boot-image:services 的预编译产物过期了
log "services.jar 打补丁完成:$(sha256sum "$WORK/services.jar" | cut -c1-16)(开机版本一致性弹窗的调用方 -> true)"
